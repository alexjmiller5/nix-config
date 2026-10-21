#!/usr/bin/env bash
# Behavioral test: capture-snapshot tcc lists live grants only. A row whose app
# is gone (bundle id Spotlight cannot find, or a client path that no longer
# exists) grants nothing and cannot be purged with SIP on, so it is not drift.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1"; exit 1; }
tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT

/usr/bin/sqlite3 "$tmp/TCC.db" "CREATE TABLE access (service TEXT, client TEXT, auth_value INT, indirect_object_identifier TEXT DEFAULT 'UNUSED');
INSERT INTO access (service,client,auth_value) VALUES
 ('kTCCServiceSystemPolicyAllFiles','org.example.live',2),
 ('kTCCServiceSystemPolicyAllFiles','org.example.gone',2),
 ('kTCCServiceScreenCapture','com.apple.screensharing.agent',2),
 ('kTCCServiceSystemPolicyAllFiles','$tmp',2),
 ('kTCCServiceSystemPolicyAllFiles','$tmp/missing-binary',2),
 ('kTCCServiceAccessibility','org.example.denied',0),
 ('kTCCServiceAccessibility','org.example.helper',2),
 ('kTCCServiceAccessibility','org.example.stale-helper',2);"

mkdir "$tmp/bin"
cat > "$tmp/bin/mdfind" <<'MD'
#!/usr/bin/env bash
case "$*" in *org.example.live*) echo /Applications/Live.app ;; esac
MD
chmod +x "$tmp/bin/mdfind"
cat > "$tmp/bin/lsregister" <<SH
#!/usr/bin/env bash
cat <<'DUMP'
path:                       $tmp (0x1234)
identifier:                 org.example.helper
path:                       $tmp/missing-helper.app (0x5678)
identifier:                 org.example.stale-helper
DUMP
SH
chmod +x "$tmp/bin/lsregister"
export CAPTURE_SNAPSHOT_LSREGISTER="$tmp/bin/lsregister"

/usr/bin/sqlite3 "$tmp/user.db" "CREATE TABLE access (service TEXT, client TEXT, auth_value INT, indirect_object_identifier TEXT DEFAULT 'UNUSED');
INSERT INTO access (service,client,auth_value,indirect_object_identifier) VALUES
 ('kTCCServiceCamera','org.example.live',2,'UNUSED'),
 ('kTCCServiceAppleEvents','org.example.live',2,'com.apple.Notes'),
 ('kTCCServiceAppleEvents','org.example.live',2,'com.apple.finder'),
 ('kTCCServicePhotos','org.example.live',3,'UNUSED'),
 ('kTCCServiceSystemPolicyAppData','org.example.live',5,'UNUSED'),
 ('kTCCServiceMicrophone','org.example.live',0,'UNUSED');"

out=$(PATH="$tmp/bin:$PATH" CAPTURE_SNAPSHOT_TCC_DB="$tmp/TCC.db" CAPTURE_SNAPSHOT_TCC_USER_DB="$tmp/user.db" ./scripts/capture-snapshot tcc)

grep -qx 'kTCCServiceSystemPolicyAllFiles|org.example.live|auth=2' <<<"$out" || fail "installed app dropped"
grep -qx 'kTCCServiceScreenCapture|com.apple.screensharing.agent|auth=2' <<<"$out" || fail "Apple client dropped"
grep -qx "kTCCServiceSystemPolicyAllFiles|$tmp|auth=2" <<<"$out" || fail "existing path client dropped"
grep -qx 'kTCCServiceAccessibility|org.example.helper|auth=2' <<<"$out" || fail "unindexed installed helper dropped"
grep -q 'org.example.stale-helper' <<<"$out" && fail "stale LaunchServices record listed"
grep -q 'org.example.gone' <<<"$out" && fail "uninstalled app listed"
grep -q 'missing-binary' <<<"$out" && fail "missing path client listed"
grep -q 'org.example.denied' <<<"$out" && fail "denied row listed"
grep -qx 'kTCCServiceCamera|org.example.live|auth=2' <<<"$out" || fail "user database camera grant dropped"
for target in com.apple.Notes com.apple.finder; do
  grep -qx "kTCCServiceAppleEvents|org.example.live|auth=2|target=$target" <<<"$out" || fail "Automation target dropped"
done
grep -qx 'kTCCServicePhotos|org.example.live|auth=3' <<<"$out" || fail "limited Photos decision dropped"
grep -qx 'kTCCServiceSystemPolicyAppData|org.example.live|auth=5' <<<"$out" || fail "nonstandard authorization lost"
grep -q 'kTCCServiceMicrophone' <<<"$out" && fail "denied user row listed"
if PATH="$tmp/bin:$PATH" CAPTURE_SNAPSHOT_TCC_DB="$tmp/TCC.db" CAPTURE_SNAPSHOT_TCC_USER_DB="$tmp/missing.db" ./scripts/capture-snapshot tcc > /dev/null 2>&1; then
  fail "unreadable user database reported as success"
else
  [ "$?" -eq 3 ] || fail "unreadable user database wrong exit code"
fi
echo "ok capture-snapshot tcc"

# The selected host must supply the capture even when this recipe runs on the mini.
cat > "$tmp/bin/ssh" <<'SH'
#!/usr/bin/env bash
[ "${SNAPSHOT_TEST_FAIL:-}" != 1 ] || exit 255
printf '%s snapshot\n' "$1"
SH
chmod +x "$tmp/bin/ssh"
git init -q "$tmp"
PATH="$tmp/bin:$PATH" AGENT_MACHINE=mini just --justfile "$PWD/justfile" --working-directory "$tmp" snapshot tcc macbook-air >/dev/null
grep -qx 'macbook-air-tailscale snapshot' "$tmp/snapshots/macbook-air/tcc.txt" || fail "snapshot used the wrong machine"
if PATH="$tmp/bin:$PATH" AGENT_MACHINE=mini SNAPSHOT_TEST_FAIL=1 just --justfile "$PWD/justfile" --working-directory "$tmp" snapshot tcc macbook-air >/dev/null 2>&1; then
  fail "failed remote capture reported as success"
fi
grep -qx 'macbook-air-tailscale snapshot' "$tmp/snapshots/macbook-air/tcc.txt" || fail "failed capture overwrote snapshot"
echo "ok snapshot host routing"
cat > "$tmp/bin/capture-snapshot" <<'SH'
#!/usr/bin/env bash
printf 'local snapshot\n'
SH
chmod +x "$tmp/bin/capture-snapshot"
PATH="$tmp/bin:$PATH" AGENT_MACHINE=mini just --justfile "$PWD/justfile" --working-directory "$tmp" snapshot tcc mac-mini >/dev/null
grep -qx 'local snapshot' "$tmp/snapshots/mac-mini/tcc.txt" || fail "local mini capture unnecessarily used SSH"
echo "ok local snapshot routing"
