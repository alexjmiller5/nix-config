# Shared by the gh/gcloud/gog wrappers (interpolated via builtins.readFile):
# ensure OP_SERVICE_ACCOUNT_TOKEN is set in agent contexts so op reads are
# headless. AGENT_SHELL is the agent-agnostic seam (mapped from per-agent
# vars in zsh.nix), but it only exists where shell init ran — agent-core
# direct spawns (e.g. claude runs `gh auth token` at every interactive
# startup) skip zshrc AND shell-init, so the raw claude vars must stay as
# fallback or those calls fall through to desktop auth and pop Touch ID.
# Alex's own terminal sets none of these, so his calls keep desktop auth.
# Adding a new agent CLI: one detection line in zsh.nix covers shells; add
# its raw var here only if its core spawns also call a wrapper.
if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && [ -n "${AGENT_SHELL:-}${CLAUDECODE:-}${CLAUDE_CODE_ENTRYPOINT:-}" ]; then
  # 0600 token file refreshed at login by op-agent-sa.nix (a file, not the
  # Keychain — ssh-descended shells can't read the per-session-locked Keychain).
  OP_SERVICE_ACCOUNT_TOKEN="$(/bin/cat "$HOME/.local/state/op/agent-sa-token" 2>/dev/null || true)"
  if [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    export OP_SERVICE_ACCOUNT_TOKEN
  else
    unset OP_SERVICE_ACCOUNT_TOKEN
  fi
fi
