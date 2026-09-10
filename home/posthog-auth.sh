# Normalize aliases before the API bundle sees them: POSTHOG_API_KEY and
# POSTHOG_HOST are often an app's public ingestion settings.
POSTHOG_CLI_API_KEY="${POSTHOG_CLI_API_KEY:-${POSTHOG_CLI_TOKEN:-}}"
if [ -z "$POSTHOG_CLI_API_KEY" ]; then
  case "${POSTHOG_API_KEY:-}" in
    phx_*)
      POSTHOG_CLI_API_KEY="$POSTHOG_API_KEY"
      POSTHOG_CLI_HOST="${POSTHOG_CLI_HOST:-${POSTHOG_HOST:-https://us.posthog.com}}"
      ;;
    *)
      if ! op_has_auth; then
        echo 'posthog-cli: no 1Password auth; set POSTHOG_CLI_API_KEY or authenticate 1Password' >&2
        exit 1
      fi
      POSTHOG_CLI_API_KEY="$(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/mmwl3dsd7kbsfc62osuj43ovvm/credential')"
      ;;
  esac
fi
if [ -z "$POSTHOG_CLI_API_KEY" ]; then
  echo 'posthog-cli: empty API key from 1Password' >&2
  exit 1
fi
export POSTHOG_CLI_API_KEY
export POSTHOG_API_KEY="$POSTHOG_CLI_API_KEY"
export POSTHOG_CLI_HOST="${POSTHOG_CLI_HOST:-https://us.posthog.com}"
export POSTHOG_HOST="$POSTHOG_CLI_HOST"
if [ -n "${POSTHOG_CLI_PROJECT_ID:-${POSTHOG_CLI_ENV_ID:-}}" ]; then
  export POSTHOG_PROJECT_ID="${POSTHOG_CLI_PROJECT_ID:-$POSTHOG_CLI_ENV_ID}"
fi
if [ -n "${POSTHOG_CLI_ORGANIZATION_ID:-}" ]; then
  export POSTHOG_ORGANIZATION_ID="$POSTHOG_CLI_ORGANIZATION_ID"
fi
