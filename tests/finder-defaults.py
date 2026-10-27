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

# Exercise both native column representations, preserving other column settings.
program = """
ObjC.import('Foundation');
const fixture = $.NSUserDefaults.alloc.initWithSuiteName('com.example.finder-columns-test');
try {
  const initial = {
    ExtendedListViewSettingsV2: {columns: [
      {identifier: 'name', visible: true, width: 321},
      {identifier: 'label', visible: true, width: 100}]},
    ListViewSettings: {columns: {name: {visible: true}, label: {visible: true}}}
  };
  fixture.setObjectForKey($(initial), 'FK_StandardViewSettings');
  fixture.setObjectForKey($(initial), 'StandardViewSettings');
  (() => { SCRIPT })();
  const result = ObjC.deepUnwrap(fixture.objectForKey('StandardViewSettings'));
  if (result.ExtendedListViewSettingsV2.columns[1].visible !== false ||
      result.ListViewSettings.columns.label.visible !== false)
    throw Error('Tags column is still visible');
  if (result.ExtendedListViewSettingsV2.columns[0].width !== 321 ||
      result.ListViewSettings.columns.name.visible !== true)
    throw Error('unrelated column settings changed');
  fixture.removeObjectForKey('StandardViewSettings');
  (() => { SCRIPT })();
  const seeded = ObjC.deepUnwrap(fixture.objectForKey('StandardViewSettings'));
  if (seeded.ExtendedListViewSettingsV2.columns[1].visible !== false ||
      seeded.ListViewSettings.columns.label.visible !== false)
    throw Error('missing column layouts were not seeded');
} finally {
  fixture.removePersistentDomainForName('com.example.finder-columns-test');
  fixture.synchronize;
}
"""
for script, succeeds in [(cleanup, True), (cleanup.replace('visible = false', 'visible = true'), False)]:
    result = subprocess.run(['/usr/bin/osascript', '-l', 'JavaScript'],
        input=program.replace('SCRIPT', script.replace('com.apple.finder', 'com.example.finder-columns-test')),
        text=True, capture_output=True)
    assert (result.returncode == 0) == succeeds, result.stderr
print('finder-defaults: Tags hidden in both column formats; other columns preserved')
