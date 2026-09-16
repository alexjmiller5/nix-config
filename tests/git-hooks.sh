#!/usr/bin/env bash
# Behavioral test for the global pre-commit hook body (home/git-pre-commit.sh):
# fails closed with no credential, propagates ggshield's verdict, and chains a
# repo's own hook (core.hooksPath replaces .git/hooks wholesale). No 1Password,
# no network, no real secrets.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1"; exit 1; }

stub=$(mktemp -d)
trap 'rm -rf "$stub"' EXIT
bashbin=$(command -v bash)   # /bin/bash 3.2 chokes on an empty "$@" under set -u

mkstub() { printf '#!/bin/sh\n%s\n' "$2" > "$stub/$1"; chmod +x "$stub/$1"; }
mkstub op 'echo key-from-vault'
# git answers only `rev-parse --git-dir`; any other query (like --git-path,
# which honors core.hooksPath and would resolve to the global hook itself)
# fails loudly so the chain step cannot recurse.
mkstub git '[ "$1 $2" = "rev-parse --git-dir" ] || { echo "unexpected git $*" >&2; exit 2; }; echo "$STUB_GIT_DIR"'
mkstub ggshield 'echo "ggshield $*" >> "$STUB_LOG"; exit "${GG_EXIT:-0}"'
mkdir -p "$stub/repo/hooks"
mkstub repo/hooks/pre-commit 'echo local-ran >> "$STUB_LOG"; exit 3'

probe() { # args: env assignments; AUTH=yes simulates a reachable op auth source
  env -i PATH="$stub:/usr/bin:/bin" STUB_LOG="$stub/log" STUB_GIT_DIR="${GIT_DIR_STUB:-$stub/empty}" "$@" \
    "$bashbin" --norc --noprofile -euo pipefail -c 'op_has_auth() { [ "${AUTH:-no}" = yes ]; }; . ./home/git-pre-commit.sh'
}

: > "$stub/log"
# No credential anywhere → refuse, and never call ggshield.
if probe 2>"$stub/err"; then fail "hook allowed a commit with no credential"; fi
grep -q "no GitGuardian credential" "$stub/err" || fail "missing fail-closed message"
[ ! -s "$stub/log" ] || fail "ggshield ran without a credential"

# Vault credential → the scan runs, and a finding blocks the commit.
if probe AUTH=yes GG_EXIT=1; then fail "hook ignored a ggshield finding"; fi
grep -q "secret scan pre-commit" "$stub/log" || fail "ggshield not invoked"

# Clean scan → the repo's own hook still runs, and its exit code is the hook's.
rc=0
GIT_DIR_STUB="$stub/repo" probe AUTH=yes || rc=$?
[ "$rc" = 3 ] || fail "repo-local hook not chained (rc=$rc)"
grep -q local-ran "$stub/log" || fail "repo-local hook did not run"

# Clean scan, no local hook → the commit proceeds.
probe AUTH=yes || fail "clean scan blocked the commit"

echo "git-hooks: all checks passed"
