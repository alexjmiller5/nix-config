# Agent context: ensure OP_SERVICE_ACCOUNT_TOKEN is set so op reads are
# headless (never Touch ID). Interpolated (builtins.readFile) into the
# gh/gcloud/gog/modal wrappers, always AFTER agent-detect.sh — this file
# gates on AGENT_SHELL alone and knows no agent CLI's raw vars. Not sourced
# by zshrc: per-call agent env is shell-init.sh's job, and the wrappers
# self-inject. Alex's own terminals have no AGENT_SHELL, so this no-ops
# and his calls keep desktop auth.
if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && [ -n "${AGENT_SHELL:-}" ]; then
  # 0600 token file refreshed at login by op-agent-sa.nix (a file, not the
  # Keychain — ssh-descended shells can't read the per-session-locked Keychain).
  OP_SERVICE_ACCOUNT_TOKEN="$(/bin/cat "$HOME/.local/state/op/agent-sa-token" 2>/dev/null || true)"
  if [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    export OP_SERVICE_ACCOUNT_TOKEN
  else
    unset OP_SERVICE_ACCOUNT_TOKEN
  fi
fi
