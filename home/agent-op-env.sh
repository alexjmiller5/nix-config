# Shared by shell startup, lifecycle hooks, CLI wrappers and Git signing.
# Explicit credentials win over a remembered desktop preference.
_agent_op_token="$(/bin/cat "${AGENT_OP_TOKEN_FILE:-$HOME/.local/state/op/agent-sa-token}" 2>/dev/null || true)"
_agent_op_desktop=
_agent_op_session="${CODEX_THREAD_ID:-${CODEX_SESSION_ID:-${AGENT_OP_SESSION:-}}}"
case "$_agent_op_session" in
  ''|*[!a-zA-Z0-9_-]*) ;;
  *)
    if [ -f "${XDG_STATE_HOME:-$HOME/.local/state}/op/auth-sessions/$_agent_op_session" ] \
      && [ -z "${OP_CONNECT_HOST:-}${OP_CONNECT_TOKEN:-}" ] \
      && { [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] || [ "$OP_SERVICE_ACCOUNT_TOKEN" = "$_agent_op_token" ]; }; then
      _agent_op_desktop=1
    fi
    ;;
esac
if [ "${AGENT_OP_AUTH:-}" = desktop ] || [ -n "$_agent_op_desktop" ]; then
  unset OP_SERVICE_ACCOUNT_TOKEN OP_CONNECT_HOST OP_CONNECT_TOKEN
elif [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && [ -n "${AGENT_SHELL:-}" ] && [ -n "$_agent_op_token" ]; then
  export OP_SERVICE_ACCOUNT_TOKEN="$_agent_op_token"
fi
unset _agent_op_token _agent_op_desktop _agent_op_session

# With no auth source, skip reads that would prompt on /dev/tty in headless
# callers. The router supplies the mini's supported user session when present.
op_has_auth() {
  [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}${OP_SESSION:-}${OP_CONNECT_TOKEN:-}" ] \
    || [ -s "$HOME/.local/state/op/personal-session" ] \
    || [ -n "$(op account list 2>/dev/null)" ]
}
