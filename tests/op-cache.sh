#!/usr/bin/env bash
# Checks for op_cached in home/op-cache.sh — the TTL cache that keeps the
# op-authed wrappers inside 1Password's account-wide 1000-requests/24h budget.
#
# Worth a test because both failure modes are silent and expensive: caching
# too little quietly re-exhausts the budget (and a hit cap breaks git without
# naming 1Password), while a broken stale-fallback hands `gh` an empty token
# and turns a rate-limit blip into a hard auth failure. Sources the real file,
# never a copy.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"

# shellcheck source=../home/op-cache.sh
. home/op-cache.sh

# Stub op: echoes $op_out, fails when $op_out is empty (the rate-limited /
# offline case). op_cached is always called inside a command substitution, so
# the call count has to live in a file to survive the subshell.
tally="$tmp/reads"
: >"$tally"
op() { echo x >>"$tally"; [ -n "$op_out" ] || return 1; printf '%s' "$op_out"; }
reads() { wc -l <"$tally" | tr -d ' '; }

op_out=secret-v1

# cold: one op read, value returned and cached at 0600
[ "$(op_cached tok 'op://v/i/f')" = secret-v1 ] || fail "cold read returned the wrong value"
[ "$(reads)" = 1 ] || fail "cold read made $(reads) op calls, expected 1"
[ -f "$HOME/.local/state/op/cache/tok" ] || fail "cold read did not write a cache file"
[ "$(/usr/bin/stat -f %Lp "$HOME/.local/state/op/cache/tok")" = 600 ] \
  || fail "cache file is not 0600 — it holds a live credential"

# warm: served from cache, op never touched (this is the whole point)
[ "$(op_cached tok 'op://v/i/f')" = secret-v1 ] || fail "warm read returned the wrong value"
[ "$(reads)" = 1 ] || fail "warm read hit op — the cache is not being used"

# expired: TTL elapsed, so it refreshes and picks up the rotated secret
op_out=secret-v2
[ "$(OP_CACHE_TTL=0 op_cached tok 'op://v/i/f')" = secret-v2 ] || fail "expired entry did not refresh"
[ "$(reads)" = 2 ] || fail "expired entry made $(reads) op calls total, expected 2"

# op down with a cached value: serve it stale rather than break the caller
op_out=
[ "$(OP_CACHE_TTL=0 op_cached tok 'op://v/i/f')" = secret-v2 ] \
  || fail "op failure did not fall back to the stale cache"

# op down with nothing cached: empty, exit 0 — callers gate on -n, and a
# nonzero return would kill the wrapper under set -e.
out=$(op_cached never-cached 'op://v/i/f') || fail "uncached miss returned nonzero under set -e"
[ -z "$out" ] || fail "uncached miss invented a value"

echo "op-cache: all checks passed"
