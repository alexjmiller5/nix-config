# TTL-cached `op read`, for the wrapper family in op-wrappers.nix.
# Interpolated (builtins.readFile) after agent-op-env.sh; defines op_cached
# and nothing else, so sourcing it is free.
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
# Rotated a cached secret? `rm -rf ~/.local/state/op/cache` — that is the
# whole invalidation story.
#
# On disk vs. the family's "nothing credential-shaped touches disk" rule: the
# cache sits beside ~/.local/state/op/agent-sa-token, the 0600 SA token that
# can already read every one of these items. Same directory, same mode, so a
# reader of the cache gains nothing they did not already have.
op_cached() {
  _oc_file="$HOME/.local/state/op/cache/$1"
  _oc_ttl="${OP_CACHE_TTL:-43200}" # 12h — no staler than the login-refreshed SA token beside it
  _oc_now="$(/bin/date +%s)"
  _oc_mtime="$(/usr/bin/stat -f %m "$_oc_file" 2>/dev/null || echo 0)"

  if [ -s "$_oc_file" ] && [ "$((_oc_now - _oc_mtime))" -lt "$_oc_ttl" ]; then
    /bin/cat "$_oc_file"
    return 0
  fi

  _oc_val="$(op read "$2" 2>/dev/null || true)"
  if [ -n "$_oc_val" ]; then
    (
      umask 077
      /bin/mkdir -p "${_oc_file%/*}"
      printf '%s' "$_oc_val" >"$_oc_file"
    )
    printf '%s' "$_oc_val"
    return 0
  fi

  # op unavailable — rate-limited, offline, or token expired. A stale secret
  # still authenticates; refusing to serve one turns a 1P hiccup into broken
  # git. Empty (never cached) falls through to the caller's own -n guard.
  if [ -s "$_oc_file" ]; then /bin/cat "$_oc_file"; fi
  return 0
}
