# TTL-cached `op read` for the wrapper family in op-wrappers.nix, plus the
# sweeper that enforces the TTL as a disk-residency limit.
# Interpolated (builtins.readFile) after agent-op-env.sh, and sourced by
# op-agent-sa.nix's sweep agent; defines two functions and two vars, nothing
# else runs, so sourcing it is free.
#
# Why this exists: 1Password meters service accounts on TWO budgets, and the
# binding one is per-1PASSWORD-ACCOUNT, not per-token — 1000 read/write
# requests per 24h shared across every service account that exists. A wrapper
# that spends one request per invocation therefore burns the whole day's
# budget on a few hundred `gh` calls, and minting another service account
# does not help: a new token draws from the same account pool. Caching is the
# only lever. Exhaustion is also silent and confusing — git stops signing
# ("failed to write commit object") and pushes stop authing ("could not read
# Username"), neither of which names 1Password.
#
# What lands on disk is the REAL secret, verbatim (the live GitHub PAT, the
# live Modal tokens). Two things bound that exposure:
#   - Mode 0600 in ~/.local/state/op/cache/, beside the 0600 SA token that
#     already grants read+write on the whole AI Agent vault. A reader of the
#     cache could have used that token to fetch the same secrets anyway, so
#     the cache adds no capability an attacker did not already have.
#   - The TTL is a HARD limit, not just a freshness check: an expired entry
#     is deleted on sight here, and op_cache_sweep deletes expired entries on
#     a timer so nothing lingers while the wrappers sit idle. A cached
#     credential is a live credential; it does not get to outlive its window
#     as a rate-limit fallback.
#
# Rotated a cached secret and don't want to wait out the TTL?
# `rm -rf ~/.local/state/op/cache` — that is the whole invalidation story.

: "${OP_CACHE_TTL:=43200}" # 12h. op_cache_sweep reads this same value, so the
# lazy and timed expiries can never disagree.
OP_CACHE_DIR="$HOME/.local/state/op/cache" # beside agent-sa-token, same mode

op_cached() {
  _oc_file="$OP_CACHE_DIR/$1"
  _oc_now="$(/bin/date +%s)"
  _oc_mtime="$(/usr/bin/stat -f %m "$_oc_file" 2>/dev/null || echo 0)"

  if [ -s "$_oc_file" ]; then
    if [ "$((_oc_now - _oc_mtime))" -lt "$OP_CACHE_TTL" ]; then
      /bin/cat "$_oc_file"
      return 0
    fi
    /bin/rm -f "$_oc_file" # past TTL: gone from disk, not kept as a fallback
  fi

  _oc_val="$(op read "$2" 2>/dev/null || true)"
  if [ -n "$_oc_val" ]; then
    (
      umask 077
      /bin/mkdir -p "$OP_CACHE_DIR"
      printf '%s' "$_oc_val" >"$_oc_file"
    )
    printf '%s' "$_oc_val"
  fi
  # op unavailable and nothing fresh cached: emit nothing and exit 0. Callers
  # gate on -n, and a nonzero return would kill the wrapper under set -e.
  return 0
}

# Delete every cached secret past the TTL. op_cached only expires entries it
# is asked for, so without this a secret would sit on disk indefinitely once
# its wrapper stopped being called.
op_cache_sweep() {
  [ -d "$OP_CACHE_DIR" ] || return 0
  /usr/bin/find "$OP_CACHE_DIR" -type f -mmin "+$((OP_CACHE_TTL / 60))" -delete
}
