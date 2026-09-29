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
mkstub ggshield 'echo "ggshield $*" >> "$STUB_LOG"; [ -z "${GG_REPORT:-}" ] || printf "%s\n" "$GG_REPORT"; exit "${GG_EXIT:-0}"'
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

# The false-positive exit. A heuristic (generic detector) finding passes only
# when the committer says what the value is; a finding in a known credential
# format never passes, alone or mixed in; a scan that failed without findings
# never passes either.
docs=https://docs.gitguardian.com/secrets-detection/secrets-detection-engine/detectors
generic=">> Secret detected: Generic High Entropy Secret
   Detector documentation: $docs/generics/generic_high_entropy_secret"
specific=">> Secret detected: Stripe Keys
   Detector documentation: $docs/specifics/stripe"
if probe AUTH=yes GG_EXIT=1 GG_REPORT="$generic" 2>"$stub/err"; then fail "finding passed without a declaration"; fi
grep -q 'FALSE_POSITIVE=' "$stub/err" || fail "refusal does not name the false-positive exit"
grep -q 'Generic High Entropy Secret' "$stub/err" || fail "refusal hides the scan report"
probe AUTH=yes GG_EXIT=1 GG_REPORT="$generic" FALSE_POSITIVE="1Password item ID" 2>"$stub/err" \
  || fail "declared heuristic finding was refused"
grep -q 'accepted as a false positive: 1Password item ID' "$stub/err" || fail "acceptance not reported"
grep -q 'archive' "$stub/err" || fail "acceptance omits the follow-up duty"
if probe AUTH=yes GG_EXIT=1 GG_REPORT="$specific" FALSE_POSITIVE="test data" 2>"$stub/err"; then
  fail "known credential format passed as a false positive"; fi
grep -q 'known credential format' "$stub/err" || fail "refusal does not explain the known format"
if probe AUTH=yes GG_EXIT=1 GG_REPORT="$generic
$specific" FALSE_POSITIVE="test data" 2>/dev/null; then fail "mixed findings passed as a false positive"; fi
if probe AUTH=yes GG_EXIT=1 GG_REPORT="Error: API unreachable" FALSE_POSITIVE="x" 2>/dev/null; then
  fail "failed scan passed as a false positive"; fi
# An accepted false positive still runs the repo's own hook.
rc=0
GIT_DIR_STUB="$stub/repo" probe AUTH=yes GG_EXIT=1 GG_REPORT="$generic" FALSE_POSITIVE="id" 2>/dev/null || rc=$?
[ "$rc" = 3 ] || fail "repo-local hook not chained after an accepted false positive (rc=$rc)"

# Clean scan → the repo's own hook still runs, and its exit code is the hook's.
rc=0
GIT_DIR_STUB="$stub/repo" probe AUTH=yes || rc=$?
[ "$rc" = 3 ] || fail "repo-local hook not chained (rc=$rc)"
grep -q local-ran "$stub/log" || fail "repo-local hook did not run"

# Clean scan, no local hook → the commit proceeds.
probe AUTH=yes || fail "clean scan blocked the commit"

echo "git-hooks: all checks passed"
