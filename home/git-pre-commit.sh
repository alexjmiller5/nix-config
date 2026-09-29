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
  echo "pre-commit: no GitGuardian credential reachable - refusing to commit unscanned changes. Restore 1Password auth and commit again (op-connect-start restarts local Connect; AGENT_OP_AUTH=desktop uses user auth for one command). git commit --no-verify skips the scan." >&2
  exit 1
fi
# A flagged commit has one sanctioned exit: FALSE_POSITIVE="<what the value
# is>" git commit ... It passes findings from the generic detectors only
# (entropy and keyword heuristics, the source of false positives). A finding
# in a known credential format never passes, and neither does a scan that
# failed without reporting findings.
if ! report="$(ggshield secret scan pre-commit --no-check-for-updates "$@" 2>&1)"; then
  printf '%s\n' "$report" >&2
  detectors="$(printf '%s\n' "$report" | grep 'Detector documentation:' || true)"
  if [ -z "$detectors" ]; then
    echo "pre-commit: the scan failed without findings - refusing to commit unscanned changes" >&2
    exit 1
  elif printf '%s\n' "$detectors" | grep -qv '/detectors/generics/'; then
    cat >&2 <<'EOF'
pre-commit: refused. A finding above matches a known credential format.
  Remove it from the change, and rotate it if it ever left this machine.
  FALSE_POSITIVE does not apply to known formats.
EOF
    exit 1
  elif [ -z "${FALSE_POSITIVE:-}" ]; then
    cat >&2 <<'EOF'
pre-commit: refused. The findings above come from heuristics, so they may be wrong.
  If the value grants access to anything, it is a secret: remove it.
  If it is not a credential (an opaque ID, a hash, a placeholder, fixture data),
  say what it is and commit again:
    FALSE_POSITIVE="<what the value is>" git commit ...
EOF
    exit 1
  fi
  cat >&2 <<EOF
pre-commit: accepted as a false positive: $FALSE_POSITIVE
  GitGuardian still opens an incident about a minute after the push. You own it:
  1. close the incident as a false positive, with the reason above as its note
  2. mark its alert email read and archive it
  How: the gitguardian skill, or dashboard.gitguardian.com and the mailbox by hand.
EOF
fi
# core.hooksPath replaces .git/hooks wholesale; keep a repo's own hook alive.
# NOT `--git-path hooks/pre-commit`: that honors core.hooksPath and resolves
# to this very script, which then re-executes itself forever.
local_hook="$(git rev-parse --git-dir)/hooks/pre-commit"
if [ -x "$local_hook" ]; then exec "$local_hook" "$@"; fi
