# The ONE place that knows agent CLIs' raw env vars: maps them to
# AGENT_SHELL, the agent-agnostic seam everything downstream gates on.
# Sourced by zshrc (op-personal gating) and interpolated (builtins.readFile)
# into the gh/gcloud/gog/modal wrappers BEFORE agent-op-env.sh, since their
# callers (agent-core direct spawns, launchd, scripts) may skip zshrc.
# Adding a new agent CLI = one more detection line here, nowhere else.
# Alex's own terminals set none of these vars, so this no-ops there.
if [ -z "${AGENT_SHELL:-}" ] && [ -n "${CLAUDECODE:-}${CLAUDE_CODE_ENTRYPOINT:-}" ]; then
  export AGENT_SHELL=claude
fi
