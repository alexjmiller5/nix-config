#!/usr/bin/env bash
# Behavioral test for op_has_auth, the shared guard every op-authed wrapper
# gates its `op` calls on (home/agent-op-env.sh). The failure it prevents:
# calling `op read` with NO auth source, which prompts on /dev/tty and hangs
# headless callers.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1"; exit 1; }

stub=$(mktemp -d)
trap 'rm -rf "$stub"' EXIT

mkstub() { printf '#!/bin/sh\n%s\n' "$1" > "$stub/op"; chmod +x "$stub/op"; }

probe() { # args: env assignments passed through `env`
  env -i PATH="$stub:/usr/bin:/bin" "$@" \
    sh -c '. ./home/agent-op-env.sh; if op_has_auth; then echo yes; else echo no; fi'
}

# No SA token and no configured desktop account → must be false.
mkstub 'exit 1'
[ "$(probe HOME="$stub")" = no ] || fail "guard allowed op calls with no auth source"

# A configured desktop account → true.
mkstub 'echo "my.1password.com  someone@example.com  USERID"'
[ "$(probe HOME="$stub")" = yes ] || fail "guard blocked op calls despite a desktop account"

# An SA token → true even when `op account list` is empty (headless machines).
mkstub 'exit 1'
[ "$(probe HOME="$stub" OP_SERVICE_ACCOUNT_TOKEN=fake)" = yes ] \
  || fail "guard blocked op calls despite a service-account token"

echo "op-auth-guard: all checks passed"
