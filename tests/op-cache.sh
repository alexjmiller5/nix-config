#!/usr/bin/env bash
# Checks for home/op-cache.sh — the TTL cache that keeps the op-authed
# wrappers inside 1Password's account-wide 1000-requests/24h budget, and the
# sweeper that stops a cached credential outliving its TTL on disk.
#
# Worth a test because every failure mode here is silent. Caching too little
# quietly re-exhausts the budget (and a hit cap breaks git without ever
# naming 1Password); expiring too little leaves a live PAT sitting in
# ~/.local/state indefinitely, which is the whole thing the TTL exists to
# prevent; and a sweep with the wrong find predicate either deletes nothing
# or deletes everything on sight. Sources the real file, never a copy.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"

# shellcheck source=../home/op-cache.sh
. home/op-cache.sh

cache="$HOME/.local/state/op/cache"

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
[ -f "$cache/tok" ] || fail "cold read did not write a cache file"
[ "$(/usr/bin/stat -f %Lp "$cache/tok")" = 600 ] \
  || fail "cache file is not 0600 — it holds a live credential"

# warm: served from cache, op never touched (this is the whole point)
[ "$(op_cached tok 'op://v/i/f')" = secret-v1 ] || fail "warm read returned the wrong value"
[ "$(reads)" = 1 ] || fail "warm read hit op — the cache is not being used"

# expired: TTL elapsed, so it refreshes and picks up the rotated secret
op_out=secret-v2
[ "$(OP_CACHE_TTL=0 op_cached tok 'op://v/i/f')" = secret-v2 ] || fail "expired entry did not refresh"
[ "$(reads)" = 2 ] || fail "expired entry made $(reads) op calls total, expected 2"

# expired + op down: the stale secret is DELETED, not served as a fallback.
# The TTL is a limit on disk residency, so an unrefreshable entry has to go.
op_out=
out=$(OP_CACHE_TTL=0 op_cached tok 'op://v/i/f') || fail "expired+op-down returned nonzero under set -e"
[ -z "$out" ] || fail "served a stale secret past its TTL instead of dropping it"
[ ! -e "$cache/tok" ] || fail "expired entry survived on disk after op could not refresh it"

# op down with nothing cached: empty, exit 0 — callers gate on -n, and a
# nonzero return would kill the wrapper under set -e.
out=$(op_cached never-cached 'op://v/i/f') || fail "uncached miss returned nonzero under set -e"
[ -z "$out" ] || fail "uncached miss invented a value"

# --- op_cache_sweep: the idle case op_cached never gets asked about ---------
mkdir -p "$cache"
printf fresh >"$cache/fresh"
printf stale >"$cache/stale"
# 13h old, i.e. past the 12h default TTL
touch -t "$(date -v-13H +%Y%m%d%H%M)" "$cache/stale"

op_cache_sweep
[ -f "$cache/fresh" ] || fail "sweep deleted a cache entry that was still inside its TTL"
[ ! -e "$cache/stale" ] || fail "sweep left an expired secret on disk"

# sweep must survive the dir not existing yet (first boot, before any wrapper runs)
rm -rf "$cache"
op_cache_sweep || fail "sweep failed when the cache dir does not exist"

echo "op-cache: all checks passed"
