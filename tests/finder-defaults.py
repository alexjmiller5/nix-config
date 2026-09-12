#!/usr/bin/env python3
"""Exercise the real cleanup through the native bridge in disposable domains."""
import json
from pathlib import Path
import subprocess
import uuid


source = (Path(__file__).resolve().parents[1] / "home/macos/finder.nix").read_text()
cleanup = source.split("<<'JXA'", 1)[1].split("\n      JXA", 1)[0]


def check(value, expected, script=cleanup):
    domain = "com.example.finder-test-" + uuid.uuid4().hex
    script = script.replace("com.apple.finder", domain)
    program = f"""
ObjC.import('Foundation');
const fixture = $.NSUserDefaults.alloc.initWithSuiteName({json.dumps(domain)});
const value = {json.dumps(value)};
const normalized = value => value == null ? 'null' : JSON.stringify(value, Object.keys(value).sort());
try {{
  if (value !== null) fixture.setObjectForKey($(value), 'ListViewSettings');
  fixture.setObjectForKey('preserved', 'UnrelatedPreference');
  (() => {{ {script} }})();
  const result = ObjC.deepUnwrap(fixture.objectForKey('ListViewSettings'));
  if (normalized(result) !== normalized({json.dumps(expected)}))
    throw Error('unexpected cleanup result: ' + JSON.stringify(result));
  if (ObjC.unwrap(fixture.stringForKey('UnrelatedPreference')) !== 'preserved')
    throw Error('unrelated preference changed');
}} finally {{
  fixture.removePersistentDomainForName({json.dumps(domain)});
  fixture.synchronize;
}}
"""
    return subprocess.run(
        ["/usr/bin/osascript", "-l", "JavaScript"], input=program,
        text=True, capture_output=True,
    )


for value, expected in [
    ({"calculateAllSizes": True}, None),
    (None, None),
    ({"calculateAllSizes": True, "iconSize": 16}, {"calculateAllSizes": True, "iconSize": 16}),
    ({"calculateAllSizes": False}, {"calculateAllSizes": False}),
]:
    result = check(value, expected)
    assert result.returncode == 0, result.stderr

broken = check({"calculateAllSizes": True}, None, cleanup.replace("prefs.synchronize;", "prefs.synchronize();"))
assert broken.returncode != 0, "native bridge regression was not detected"
print("finder-defaults: native cleanup, absence, data preservation, and bridge regression passed")
