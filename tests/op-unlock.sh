#!/usr/bin/env bash
# Behavioral test for the op-unlock body (home/op-unlock.sh) with op,
# launchctl, ssh, expect, sleep and date stubbed: status sees the real user
# session even in agent shells, request does nothing while a window is open,
# a failed sign-in keeps the open window, and the keepalive survives transient
# check failures but ends (and says why) when the session is gone.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1"; exit 1; }

stub=$(mktemp -d)
trap 'rm -rf "$stub"' EXIT
bashbin=$(command -v bash)   # /bin/bash 3.2 chokes on an empty "$@" under set -u
home="$stub/home"
f="$home/.local/state/op/personal-session"

mkstub() { printf '#!/bin/sh\n%s\n' "$2" > "$stub/$1"; chmod +x "$stub/$1"; }
# Like the real CLI, an inherited service-account token answers everything.
mkstub op '[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && exit 0
tok=; if [ "$1" = --session ]; then tok=$2; shift 2; fi
echo "op $* $tok" >> "$STUB_LOG"
case "$1" in signout) exit 0 ;; signin) echo token-typed; exit 0 ;; esac
n=$(cat "$STUB_FAILS"); if [ "$n" -gt 0 ]; then echo $((n - 1)) > "$STUB_FAILS"; echo "[ERROR] network is unreachable" >&2; exit 1; fi
[ "$tok" = "$(cat "$STUB_LIVE")" ] || { echo "[ERROR] You are not currently signed in" >&2; exit 1; }'
mkstub launchctl 'echo "launchctl $1" >> "$STUB_LOG"'
mkstub ssh 'echo ssh >> "$STUB_LOG"'
mkstub expect '[ "$OP_PW" = right ] || { echo "You are not currently signed in" >&2; exit 1; }; echo token-new'
mkstub sleep 'echo $(($(cat "$STUB_CLOCK") + $1)) > "$STUB_CLOCK"'
mkstub date '[ "$1" = +%s ] && exec cat "$STUB_CLOCK"; exec /bin/date "$@"'

# reset <token in the session file ("" = none)> <live server-side token> [transient failures]
reset() {
  rm -rf "$home"; mkdir -p "$(dirname "$f")"
  [ -z "$1" ] || echo "$1" > "$f"
  echo "$2" > "$stub/live"; echo "${3:-0}" > "$stub/fails"; echo 1000000 > "$stub/clock"
  : > "$stub/log"
}
run() { # run <op-unlock args>; SA=1 runs it from an agent shell with the SA token exported
  env -i PATH="$stub:/usr/bin:/bin" HOME="$home" STUB_LOG="$stub/log" STUB_LIVE="$stub/live" \
    STUB_FAILS="$stub/fails" STUB_CLOCK="$stub/clock" ${SA:+OP_SERVICE_ACCOUNT_TOKEN=sa-token} \
    "$bashbin" --norc --noprofile -euo pipefail -c 'signin_exp=/stub.exp; . ./home/op-unlock.sh' op-unlock "$@"
}
calls() { grep -c "^$1" "$stub/log" || true; }

reset token-dead token-live
[ "$(SA=1 run status)" = locked ] || fail "status in an agent shell: the SA token masked a dead session"
[ -r "$f" ] || fail "status deleted the session file (it must only report)"
reset token-live token-live
case "$(SA=1 run status)" in unlocked*) ;; *) fail "status: live session not reported unlocked" ;; esac

reset token-live token-live
SA=1 run request "need Personal" >/dev/null
[ "$(calls ssh)" = 0 ] || fail "request: prompted the laptop while a window is open"
reset "" token-live
SA=1 run request "need Personal" >/dev/null
[ "$(calls ssh)" = 1 ] || fail "request: locked mini did not ask the laptop"

reset token-live token-live
echo wrong | run --stdin 24 >/dev/null 2>&1 && fail "--stdin: wrong password reported success"
[ "$(calls 'launchctl remove')" = 0 ] || fail "--stdin: wrong password stopped the open window's keepalive"
[ "$(cat "$f")" = token-live ] || fail "--stdin: wrong password replaced the session file"
echo right | run --stdin 24 >/dev/null
[ "$(cat "$f")" = token-new ] && [ "$(calls 'launchctl submit')" = 1 ] || fail "--stdin: right password did not start a window"

reset token-live token-live 2
run keepalive 1
[ "$(cat "$stub/clock")" -ge 1003600 ] || fail "keepalive: two transient check failures ended the window early"
grep -q "window ended: deadline" "$home/.local/state/op/op-unlock.log" || fail "keepalive: deadline not logged"
[ ! -e "$f" ] && [ "$(calls 'op signout')" = 1 ] && [ "$(calls 'launchctl remove')" = 1 ] \
  || fail "keepalive: deadline did not sign out, delete the file and remove its job"

reset token-live token-other
run keepalive 1
[ "$(cat "$stub/clock")" -lt 1003600 ] || fail "keepalive: dead session kept the window open"
grep -q "not currently signed in" "$home/.local/state/op/op-unlock.log" || fail "keepalive: did not log why the session check failed"

echo "op-unlock: all checks passed"
