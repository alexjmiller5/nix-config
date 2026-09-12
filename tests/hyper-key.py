#!/usr/bin/env python3
"""Exercise native Hyper preferences in disposable domains; never remap input."""

import json
import plistlib
from pathlib import Path
import shlex
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
expression = r'''
let
  flake = builtins.getFlake ROOT;
  make = enabled: extra: (flake.inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = flake.inputs.nixpkgs.legacyPackages.aarch64-darwin;
    modules = [MODULE {
      home.username = "fixture";
      home.homeDirectory = "/tmp/hyper-key-fixture";
      home.stateVersion = "26.05";
      macos.hyperKey.enable = enabled;
    } extra];
  }).config;
in {
  active = {
    script = (make true {}).home.activation.nativeHyperKey.data;
    agents = (make true {}).launchd.agents;
    marker = (make true {}).xdg.configFile."hammerspoon/native-hyper".text;
  };
  inactive = {
    hasActivation = (make false {}).home.activation ? nativeHyperKey;
    agents = (make false {}).launchd.agents;
    hasMarker = (make false {}).xdg.configFile ? "hammerspoon/native-hyper";
  };
  custom = (make true { macos.hyperKey.keyboardKey = "1234-5678-0"; }).launchd.agents.native-hyper-key.config.ProgramArguments;
}
'''.replace("ROOT", json.dumps(str(ROOT))).replace("MODULE", str(ROOT / "home/macos/hyper-key.nix"))
result = subprocess.run(["nix", "eval", "--impure", "--json", "--expr", expression], text=True, capture_output=True)
assert result.returncode == 0, result.stderr
config = json.loads(result.stdout)
assert config["inactive"] == {"hasActivation": False, "agents": {}, "hasMarker": False}
active = config["active"]
assert active["marker"] == "rightctrl\n"
launch = active["agents"]["native-hyper-key"]["config"]
assert launch["RunAtLoad"] is True
args = launch["ProgramArguments"]
assert shlex.split(active["script"].split("\nJXA\n", 1)[1].strip()) == ["run", *args]
assert args[:2] == ["/usr/bin/hidutil", "property"]
assert json.loads(args[args.index("--matching") + 1]) == {
    "VendorID": 0, "ProductID": 0, "PrimaryUsagePage": 1, "PrimaryUsage": 6
}
assert json.loads(args[args.index("--set") + 1]) == {"UserKeyMapping": [
    {"HIDKeyboardModifierMappingSrc": 30064771129, "HIDKeyboardModifierMappingDst": 30064771300}
]}
assert json.loads(config["custom"][config["custom"].index("--matching") + 1]) == {
    "VendorID": 1234, "ProductID": 5678, "PrimaryUsagePage": 1, "PrimaryUsage": 6
}
script = active["script"].split("<<'JXA'", 1)[1].split("\nJXA", 1)[0]
pair = {"HIDKeyboardModifierMappingSrc": 30064771129, "HIDKeyboardModifierMappingDst": 30064771300}
old = pair | {"HIDKeyboardModifierMappingDst": 30064771072}
unrelated = {"HIDKeyboardModifierMappingSrc": 30064771299, "HIDKeyboardModifierMappingDst": 30064771298, "metadata": "preserve 'unknown' fields"}


def check(value, expected, body=script, fails=False):
    domain = "com.example.hyper-key-test-" + uuid.uuid4().hex
    key = "com.apple.keyboard.modifiermapping.0-0-0"
    body = body.replace("const domain = '-g';", f"const domain = {json.dumps(domain)};")
    command = ["/usr/bin/defaults", "-currentHost"]
    try:
        subprocess.run(command + ["write", domain, "unrelated", "preserved"], check=True, capture_output=True)
        if value is not None:
            subprocess.run(command + ["write", domain, key, plistlib.dumps(value).decode()], check=True, capture_output=True)
        result = subprocess.run(["/usr/bin/osascript", "-l", "JavaScript"], input=body, text=True, capture_output=True)
        assert (result.returncode != 0) == fails, result.stderr
        exported = subprocess.run(command + ["export", domain, "-"], check=True, capture_output=True)
        actual = plistlib.loads(exported.stdout)
        assert actual["unrelated"] == "preserved", "unrelated preference changed"
        assert actual[key] == expected, f"native mapping mismatch: {actual[key]!r} != {expected!r}"
        if not fails:
            assert all(type(pair[field]) is int for pair in actual[key] for field in pair if field.startswith("HIDKeyboardModifierMapping")), "HID values must remain native integers"
    finally:
        subprocess.run(command + ["delete", domain], check=True, capture_output=True)


for value, expected, fails in [
    (None, [pair], False),
    ([unrelated, old], [unrelated, pair], False),
    ([unrelated, pair], [unrelated, pair], False),
    ([old, pair], [pair], False),
    ({"malformed": True}, {"malformed": True}, True),
]:
    check(value, expected, fails=fails)
try:
    check([unrelated, old], [unrelated, pair], script.replace("30064771300", "30064771296"))
except AssertionError as error:
    assert "native mapping mismatch" in str(error), str(error)
else:
    raise AssertionError("wrong HID usage mutation survived")
print("hyper-key: opt-in, marker, keyboard-scoped boot fallback, native merge, preservation, malformed data, and mutation passed")
