#!/usr/bin/env bash
# Behavioral test: capture-snapshot tcc lists live grants only. A row whose app
# is gone (bundle id Spotlight cannot find, or a client path that no longer
# exists) grants nothing and cannot be purged with SIP on, so it is not drift.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1"; exit 1; }
tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT

/usr/bin/sqlite3 "$tmp/TCC.db" "CREATE TABLE access (service TEXT, client TEXT, auth_value INT);
INSERT INTO access VALUES
 ('kTCCServiceSystemPolicyAllFiles','org.example.live',2),
 ('kTCCServiceSystemPolicyAllFiles','org.example.gone',2),
 ('kTCCServiceScreenCapture','com.apple.screensharing.agent',2),
 ('kTCCServiceSystemPolicyAllFiles','$tmp',2),
 ('kTCCServiceSystemPolicyAllFiles','$tmp/missing-binary',2),
 ('kTCCServiceAccessibility','org.example.denied',0);"

mkdir "$tmp/bin"
cat > "$tmp/bin/mdfind" <<'MD'
#!/usr/bin/env bash
case "$*" in *org.example.live*) echo /Applications/Live.app ;; esac
MD
chmod +x "$tmp/bin/mdfind"

out=$(PATH="$tmp/bin:$PATH" CAPTURE_SNAPSHOT_TCC_DB="$tmp/TCC.db" ./scripts/capture-snapshot tcc)

grep -qx 'kTCCServiceSystemPolicyAllFiles|org.example.live' <<<"$out" || fail "installed app dropped"
grep -qx 'kTCCServiceScreenCapture|com.apple.screensharing.agent' <<<"$out" || fail "Apple client dropped"
grep -qx "kTCCServiceSystemPolicyAllFiles|$tmp" <<<"$out" || fail "existing path client dropped"
grep -q 'org.example.gone' <<<"$out" && fail "uninstalled app listed"
grep -q 'missing-binary' <<<"$out" && fail "missing path client listed"
grep -q 'org.example.denied' <<<"$out" && fail "denied row listed"
echo "ok capture-snapshot tcc"
