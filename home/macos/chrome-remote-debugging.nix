{
  pkgs,
  lib,
  config,
  ...
}:

# Chrome's remote-debugging opt-in (chrome://inspect/#remote-debugging), the
# toggle that lets CDP clients attach to the REAL logged-in profile. Since
# Chrome 136 --remote-debugging-port is ignored on the default user-data-dir,
# so this approval-mode flow is the only route onto Alex's actual session -
# see the chrome-control skill.
#
# Lives in Local State (browser-wide, NOT per-profile) and is not a protected
# pref, so there's no MAC to forge. Chrome rewrites Local State on shutdown,
# so the write is skipped while Chrome runs and converges on a later switch.
#
# This only declares the one-time checkbox. Each individual CDP connection
# still raises an "Allow remote debugging?" dialog that a human must accept -
# by design, with no allowlist. Nothing here makes CDP unattended.
let
  cfg = config.chrome.remoteDebugging;
in
{
  options.chrome.remoteDebugging.enable = lib.mkEnableOption "Chrome's chrome://inspect remote-debugging opt-in";

  config = lib.mkIf cfg.enable {
    home.activation.chromeRemoteDebugging = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      CHROME_LOCAL_STATE="$HOME/Library/Application Support/Google/Chrome/Local State" \
      ${pkgs.python3}/bin/python3 - <<'PYEOF'
      import json, os, subprocess, sys

      path = os.environ["CHROME_LOCAL_STATE"]
      if not os.path.isfile(path):
          sys.exit(0)  # Chrome never launched; converge later

      with open(path) as f:
          state = json.load(f)

      cur = state.get("devtools", {}).get("remote_debugging", {}).get("user-enabled")
      if cur is True:
          sys.exit(0)

      if subprocess.run(["/usr/bin/pgrep", "-x", "Google Chrome"],
                        capture_output=True).returncode == 0:
          print("chrome.remoteDebugging: Chrome is running; skipping "
                "(re-switch with Chrome quit)", file=sys.stderr)
          sys.exit(0)

      state.setdefault("devtools", {}).setdefault("remote_debugging", {})
      state["devtools"]["remote_debugging"]["user-enabled"] = True
      tmp = path + ".nix-tmp"
      with open(tmp, "w") as f:
          json.dump(state, f, separators=(",", ":"))
      os.replace(tmp, path)
      print("chrome.remoteDebugging: enabled", file=sys.stderr)
      PYEOF
    '';
  };
}
