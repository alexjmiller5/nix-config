#!/usr/bin/env bash
# The gog wrapper's token step (home/gog-access-token.sh) without 1Password or Google:
# op and curl are shell stubs that log their argv and stdin, so the test also proves no
# secret reaches argv.
set -euo pipefail
cd "$(dirname "$0")/.."
work="$(mktemp -d)"
trap 'rm -r "$work"' EXIT

item() { # $1 = access_token value, $2 = expires_at, $3 = include the cache fields
  jq -n --arg at "$1" --arg exp "$2" --arg with "$3" '{
    id: "jjc6xu22cew46e6zpyfdsdjv3e", title: "Token Export", tags: ["AI Agent", "Sensitive"],
    fields: ([{id: "credential", type: "CONCEALED", label: "credential",
               value: ({refresh_token: "rt-secret"} | tojson)}]
      + (if $with == "yes" then [
          {id: "a1", type: "CONCEALED", label: "access_token", value: $at},
          {id: "e1", type: "STRING", label: "expires_at", value: $exp}] else [] end))}'
}

probe() { # env assignments for the stubs, then: prints the token; logs land in $work
  rm -f "$work"/*.log "$work"/edit.json "$work"/curl.in
  env -i PATH=/usr/bin:/bin WORK="$work" "$@" bash -euo pipefail -c '
    op_has_auth() { [ "${AUTH:-yes}" = yes ]; }
    op() {
      echo "op $*" >>"$WORK/argv.log"
      case "$1 $2" in
        "item get") printf "%s" "$ITEM" ;;
        "read op://"*) printf "%s" "{\"installed\":{\"client_id\":\"cid\",\"client_secret\":\"csec-secret\"}}" ;;
        "item edit") cat >"$WORK/edit.json"; [ "${EDIT_FAILS:-no}" = no ] ;;
        *) return 9 ;;
      esac
    }
    curl() { echo "curl $*" >>"$WORK/argv.log"; cat >"$WORK/curl.in"; printf "%s" "$RESP"; }
    . ./home/gog-access-token.sh
  '
}

fail() { echo "FAIL: $*"; exit 1; }
now="$(date +%s)"
fresh="$(item at-cached "$((now + 600))" yes)"
stale="$(item at-cached "$((now + 30))" yes)"
grant='{"access_token":"at-new-secret","expires_in":3599}'

# Fast path: a cached token with more than a minute left, one op call, no refresh.
[ "$(probe ITEM="$fresh")" = at-cached ] || fail "fresh token not printed"
[ ! -e "$work/curl.in" ] || fail "fresh token refreshed anyway"
[ "$(wc -l <"$work/argv.log" | tr -d ' ')" = 1 ] || fail "fast path made more than one op call"

# Slow path: refresh through stdin, cache the pair back through a stdin template.
[ "$(probe ITEM="$stale" RESP="$grant")" = at-new-secret ] || fail "refreshed token not printed"
grep -q 'refresh_token=rt-secret' "$work/curl.in" || fail "refresh token not sent on stdin"
grep -q 'client_secret=csec-secret' "$work/curl.in" || fail "client secret not sent on stdin"
if grep -qE 'secret|at-new|at-cached' "$work/argv.log"; then fail "a secret reached argv"; fi
grep -q '^op item edit jjc6xu22cew46e6zpyfdsdjv3e --vault 4eeyrkqibibn7k4j6rz2fbzvxm$' "$work/argv.log" \
  || fail "writeback did not edit the token item by id"
jq -e --argjson now "$now" '
  ([.fields[] | select(.label == "access_token")][0].value == "at-new-secret")
  and (([.fields[] | select(.label == "expires_at")][0].value | tonumber) - $now | . >= 3599 and . <= 3605)
  and ([.fields[] | select(.id == "credential")][0].value | fromjson | .refresh_token == "rt-secret")
  and (.tags == ["AI Agent", "Sensitive"])' "$work/edit.json" >/dev/null \
  || fail "writeback template wrong: $(jq -c '[.fields[] | {label}], .tags' "$work/edit.json")"

# An item without the cache fields gets them added, not dropped.
[ "$(probe ITEM="$(item '' '' no)" RESP="$grant")" = at-new-secret ] || fail "first refresh"
jq -e '[.fields[].label] == ["credential", "access_token", "expires_at"]' "$work/edit.json" >/dev/null \
  || fail "cache fields not added"

# A failed writeback still yields the token.
[ "$(probe ITEM="$stale" RESP="$grant" EDIT_FAILS=yes)" = at-new-secret ] || fail "failed writeback"

# A revoked refresh token: the bootstrap hint on stderr, nothing on stdout, exit 1.
if out="$(probe ITEM="$stale" RESP='{"error":"invalid_grant"}' 2>"$work/err")"; then
  fail "revoked refresh token exited 0"
fi
[ -z "$out" ] || fail "revoked refresh token printed something"
grep -q 'token refresh failed (invalid_grant) - refresh token likely revoked' "$work/err" \
  || fail "revoked refresh token message: $(cat "$work/err")"
[ ! -e "$work/edit.json" ] || fail "a failed refresh wrote the item"

# No 1Password auth: fail without calling op (it would prompt on /dev/tty).
if probe AUTH=no ITEM="$fresh" 2>/dev/null; then fail "no auth exited 0"; fi
[ ! -e "$work/argv.log" ] || fail "op called without auth"

echo 'gog-access-token: all checks passed'
