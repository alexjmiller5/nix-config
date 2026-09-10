#!/usr/bin/env bash
# Exercise credential precedence without 1Password access or real secrets.
set -euo pipefail
cd "$(dirname "$0")/.."

probe() {
  env -i PATH=/usr/bin:/bin "$@" sh -eu -c '
    op_has_auth() { [ "${AUTH_AVAILABLE:-yes}" = yes ]; }
    op() {
      [ "${OP_FAIL:-no}" != yes ] || return 1
      [ "$1" = read ] || return 1
      printf phx_vault
    }
    . ./home/posthog-auth.sh
    if [ "${CHECK_CONTEXT:-no}" = yes ]; then
      printf "%s|%s" "${POSTHOG_PROJECT_ID:-}" "${POSTHOG_ORGANIZATION_ID:-}"
    else
      printf "%s|%s|%s" "$POSTHOG_CLI_API_KEY" "$POSTHOG_API_KEY" "$POSTHOG_HOST"
    fi
  '
}

expect() {
  local wanted=$1
  shift
  local actual
  actual=$(probe "$@")
  [ "$actual" = "$wanted" ] || { echo "FAIL: $actual != $wanted"; exit 1; }
}

expect 'phx_vault|phx_vault|https://us.posthog.com'
# An app's public token and ingestion host must not redirect agent auth.
expect 'phx_vault|phx_vault|https://us.posthog.com' \
  POSTHOG_API_KEY=phc_public POSTHOG_HOST=https://eu.i.posthog.com
# Explicit CLI credentials win and require no 1Password auth.
expect 'phx_cli|phx_cli|https://eu.posthog.com' AUTH_AVAILABLE=no \
  POSTHOG_CLI_API_KEY=phx_cli POSTHOG_API_KEY=phc_public \
  POSTHOG_CLI_HOST=https://eu.posthog.com
expect 'phx_legacy|phx_legacy|https://us.posthog.com' AUTH_AVAILABLE=no \
  POSTHOG_CLI_TOKEN=phx_legacy
# A caller's personal key and matching host remain a supported override.
expect 'phx_caller|phx_caller|https://eu.posthog.com' AUTH_AVAILABLE=no \
  POSTHOG_API_KEY=phx_caller POSTHOG_HOST=https://eu.posthog.com
expect 'requested-project|requested-org' CHECK_CONTEXT=yes \
  POSTHOG_CLI_PROJECT_ID=requested-project POSTHOG_PROJECT_ID=inherited-project \
  POSTHOG_CLI_ORGANIZATION_ID=requested-org POSTHOG_ORGANIZATION_ID=inherited-org
expect 'legacy-project|' CHECK_CONTEXT=yes \
  POSTHOG_CLI_ENV_ID=legacy-project POSTHOG_PROJECT_ID=inherited-project
# Fail closed instead of falling back to a credential file or prompting.
if probe AUTH_AVAILABLE=no >/dev/null 2>&1; then
  echo 'FAIL: missing 1Password auth was accepted'; exit 1
fi
if probe OP_FAIL=yes >/dev/null 2>&1; then
  echo 'FAIL: a failed credential read was accepted'; exit 1
fi
echo 'posthog-auth: all checks passed'
