# Body of the global git pre-commit hook. Interpolated into home/git-hooks.nix
# after agent-detect.sh + agent-op-env.sh (which define op_has_auth); run by
# tests/git-hooks.sh with stubs. Expects op, ggshield and git on PATH.
# A caller-set GITGUARDIAN_API_KEY wins; otherwise the scan key is read from
# the AI Agent vault ("AI Agent GitGuardian API Key") at commit time.
if [ -z "${GITGUARDIAN_API_KEY:-}" ] && op_has_auth; then
  GITGUARDIAN_API_KEY="$(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/oezu63v4l5i7j6dy5iellelxju/credential' || true)"
  export GITGUARDIAN_API_KEY
fi
if [ -z "${GITGUARDIAN_API_KEY:-}" ]; then
  echo "pre-commit: no GitGuardian credential reachable - refusing to commit unscanned changes (git commit --no-verify to bypass)" >&2
  exit 1
fi
ggshield secret scan pre-commit --no-check-for-updates "$@"
# core.hooksPath replaces .git/hooks wholesale; keep a repo's own hook alive.
# NOT `--git-path hooks/pre-commit`: that honors core.hooksPath and resolves
# to this very script, which then re-executes itself forever.
local_hook="$(git rev-parse --git-dir)/hooks/pre-commit"
if [ -x "$local_hook" ]; then exec "$local_hook" "$@"; fi
