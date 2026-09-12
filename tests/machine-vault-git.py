#!/usr/bin/env python3
"""Exercise generated bootstrap shell and installed Git config without credentials/network."""

import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
GIT = shutil.which("git")


def run(*args, **kwargs):
    return subprocess.run(args, text=True, capture_output=True, check=True, **kwargs).stdout


def script(path, text):
    path.write_text("#!/bin/sh\nset -eu\n" + text)
    path.chmod(0o755)


with tempfile.TemporaryDirectory() as directory:
    tmp = Path(directory)
    (tmp / "bin").mkdir()
    (tmp / "machine-sa").write_text("fixture-machine-token")
    env = {
        "HOME": directory,
        "PATH": f"{tmp}/bin:/usr/bin:/bin",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": str(tmp / "gitconfig"),
        "GIT_TERMINAL_PROMPT": "0",
    }
    # Evaluate the real module with generic values and stub executable paths.
    module = json.loads(run("nix", "eval", "--impure", "--json", "--expr", f'''
      let
        flake = builtins.getFlake {json.dumps(str(ROOT))};
        lib = flake.inputs.nixpkgs.lib // {{ hm.dag.entryAfter = after: data: {{ inherit data; }}; }};
      in (import {ROOT}/home/machine-vault-git.nix {{
        inherit lib;
        config.machineVaultGit = {{
          patOpRef = "op://fixture-vault/fixture-item/credential";
          patAuthFile = "{tmp}/machine-sa";
          patRepos = [ "fixture/private" ];
          companionRepos = {{
            "fixture/private" = "{tmp}/private clone";
            "fixture/public" = "{tmp}/public";
          }};
        }};
        pkgs = {{
          git = "{tmp}";
          _1password-cli = "{tmp}";
          writeShellScript = name: text: builtins.toFile name text;
          writeShellApplication = args: args;
        }};
      }}).config
    ''', cwd=ROOT))
    assert "programs" not in module, "machine module still installs Git credentials"
    assert not module.get("home", {}).get("activation"), "switch can still read bootstrap credentials"
    command = module["home"]["packages"][0]
    assert command["name"] == "bootstrap-companion-repos"
    text = command["text"]
    for i, source in enumerate(set(re.findall(r"/nix/store/[\w-]+git-credential[\w-]*", text))):
        helper = tmp / f"helper-{i}"
        script(helper, Path(source).read_text())
        text = text.replace(source, str(helper))
    script(tmp / "bootstrap", text)
    script(tmp / "bin/op", '''
      [ "$*" = "read op://fixture-vault/fixture-item/credential" ]
      [ "$OP_SERVICE_ACCOUNT_TOKEN" = fixture-machine-token ]
      [ -z "${OP_CONNECT_HOST:-}${OP_CONNECT_TOKEN:-}" ]
      echo read >> "$HOME/op-calls"
      [ ! -f "$HOME/op-fail" ] || exit 1
      echo fixture-pat
    ''')
    # Stub transport, but use real Git to resolve the command's credential options.
    script(tmp / "bin/git", f'''
      echo "$*" >> "$HOME/git-calls"
      exec {shutil.which("python3")} "$HOME/git-stub.py" "$@"
    ''')
    (tmp / "git-stub.py").write_text(f'''
import os, subprocess, sys
from pathlib import Path
args = sys.argv[1:]
index = args.index("clone")
url, dest = args[-2:]
if url == "https://github.com/fixture/private.git":
    result = subprocess.run([{GIT!r}, *args[:index], "credential", "fill"],
        input="url=" + url + "\\n\\n", text=True, capture_output=True)
    if result.returncode: sys.exit(result.returncode)
    assert "username=x-access-token\\n" in result.stdout
    assert "password=fixture-pat\\n" in result.stdout
else:
    assert not any("helper-" in arg for arg in args)
Path(dest).mkdir()
(Path(dest) / ".git").mkdir()
''')
    # A stale/inherited helper must not be called during the private clone.
    (tmp / "gitconfig").write_text('[credential]\n\thelper = !exit 99\n')
    run(str(tmp / "bootstrap"), env=env | {
        "OP_CONNECT_HOST": "https://example.invalid", "OP_CONNECT_TOKEN": "fixture-connect-token",
    })
    assert (tmp / "op-calls").read_text() == "read\n"
    assert len((tmp / "git-calls").read_text().splitlines()) == 2
    assert (tmp / "gitconfig").read_text() == '[credential]\n\thelper = !exit 99\n'
    (tmp / "machine-sa").unlink()
    run(str(tmp / "bootstrap"), env=env)
    assert (tmp / "op-calls").read_text() == "read\n", "existing clone read bootstrap token"
    assert len((tmp / "git-calls").read_text().splitlines()) == 2
    # Helper protocol: store/erase and wrong hosts/repos cannot read a token.
    for operation, request in [
        ("store", ""), ("erase", ""),
        ("get", "protocol=https\nhost=example.invalid\npath=fixture/private.git\n\n"),
        ("get", "protocol=https\nhost=github.com\npath=fixture/other.git\n\n"),
        ("get", "protocol=http\nhost=github.com\npath=fixture/private.git\n\n"),
    ]:
        assert run(str(helper), operation, input=request, env=env) == ""
    assert (tmp / "op-calls").read_text() == "read\n"
    (tmp / "private clone/.git").rmdir()
    # Home Manager may have created plugin links before the first clone.
    result = subprocess.run([str(tmp / "bootstrap")], env=env, text=True, capture_output=True)
    assert result.returncode and "exists without .git" in result.stderr
    assert (tmp / "op-calls").read_text() == "read\n"
    assert len((tmp / "git-calls").read_text().splitlines()) == 2
    (tmp / "private clone").rmdir()
    result = subprocess.run([str(tmp / "bootstrap")], env=env, text=True, capture_output=True)
    assert result.returncode and not (tmp / "private clone").exists()
    (tmp / "machine-sa").write_text("fixture-machine-token")
    (tmp / "op-fail").touch()
    result = subprocess.run([str(tmp / "bootstrap")], env=env, text=True, capture_output=True)
    assert result.returncode and not (tmp / "private clone").exists()
    assert "password=" not in result.stdout
    print("bootstrap: clone-only reads, existing clones skip, scoped helper, failures propagate")

    for host, job in [("macbook-air", "agent-config-sync"), ("mac-mini", "agent-config-pull")]:
        actual = json.loads(run("nix", "eval", "--json",
            f".#darwinConfigurations.{host}.config.home-manager.users", "--apply", f'''
            users: let hm = builtins.head (builtins.attrValues users); in {{
              git = hm.xdg.configFile."git/config".text;
              activation = builtins.hasAttr "companionRepos" hm.home.activation;
              env = hm.launchd.agents.{job}.config.EnvironmentVariables;
            }}''', cwd=ROOT))
        assert not actual["activation"]
        assert not re.search(r"machine-vault|machine-sa|op://", actual["git"])
        (tmp / "gitconfig").write_text(actual["git"])
        (tmp / "op-calls").unlink(missing_ok=True)
        # Actual launchd marker reaches the unchanged gh auth initializer.
        token = tmp / ".local/state/op/agent-sa-token"
        token.parent.mkdir(parents=True, exist_ok=True)
        token.write_text("fixture-operator-token")
        wrapper = (ROOT / "home/op-wrappers.nix").read_text().split('name = "gh";', 1)[1]
        wrapper = wrapper.split("text = ''", 1)[1].split("\n      '';", 1)[0]
        for source in ["agent-detect.sh", "agent-op-env.sh"]:
            wrapper = wrapper.replace("${builtins.readFile ./" + source + "}", (ROOT / "home" / source).read_text())
        wrapper = wrapper.replace("''${", "${").replace("${pkgs.gh}/bin/gh", str(tmp / "real-gh"))
        script(tmp / "bin/gh", wrapper)
        script(tmp / "bin/op", '''
          [ "$1" = read ]
          [ "$OP_SERVICE_ACCOUNT_TOKEN" = fixture-operator-token ]
          echo operator-read >> "$HOME/op-calls"
          echo fixture-operator-pat
        ''')
        script(tmp / "real-gh", '''
          [ "$GH_TOKEN" = fixture-operator-pat ]
          [ "$*" = "auth git-credential get" ]
          printf 'username=x-access-token\\npassword=fixture-operator-pat\\n'
        ''')
        out = run(GIT, "credential", "fill", input="url=https://github.com/fixture/private.git\n\n",
            env=env | actual["env"])
        assert "password=fixture-operator-pat" in out
        assert (tmp / "op-calls").read_text() == "operator-read\n"
        print(f"{host}: installed Git uses operator helper from launchd, no bootstrap reference")
