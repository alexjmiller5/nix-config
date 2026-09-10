# Two jobs, both needed by every op-authed wrapper. (1) Agent context: ensure
# OP_SERVICE_ACCOUNT_TOKEN is set so op reads are headless (never Touch ID).
# (2) Define op_has_auth, the shared guard those wrappers gate their op calls
# on. Interpolated (builtins.readFile) into the wrappers, always AFTER
# agent-detect.sh - this file gates on AGENT_SHELL alone and knows no agent
# CLI's raw vars. agent-env.nix also installs both as the shared initializer
# for zshenv and lifecycle hooks. Alex's own terminals have no
# AGENT_SHELL, so the arming no-ops and his calls keep desktop auth.
if [ "${AGENT_OP_AUTH:-}" = desktop ]; then
  # Explicit user auth stays selected across hooks, wrappers and child shells.
  unset OP_SERVICE_ACCOUNT_TOKEN OP_CONNECT_HOST OP_CONNECT_TOKEN
elif [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && [ -n "${AGENT_SHELL:-}" ]; then
  # 0600 token file refreshed at login by op-agent-sa.nix (a file, not the
  # Keychain — ssh-descended shells can't read the per-session-locked Keychain).
  OP_SERVICE_ACCOUNT_TOKEN="$(/bin/cat "$HOME/.local/state/op/agent-sa-token" 2>/dev/null || true)"
  if [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    export OP_SERVICE_ACCOUNT_TOKEN
  else
    unset OP_SERVICE_ACCOUNT_TOKEN
  fi
fi

# True when op can read WITHOUT prompting: an SA token (headless) or a
# configured desktop account (Touch ID). With neither — Alex's own ssh shells
# on the mini — `op read` asks "add an account?" on /dev/tty and hangs or
# garbles headless callers, and 2>/dev/null does not suppress a prompt. So
# every wrapper skips its op calls unless this returns true; none of them may
# call op unguarded.
op_has_auth() {
  [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] || [ -n "$(op account list 2>/dev/null)" ]
}
