#!/usr/bin/env bash
# Behavioral test for the shared agent-shell detection seam.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1"; exit 1; }

detected=$(
  env -i PATH="$PATH" CODEX_SESSION_ID=test-session \
    sh -c '. ./home/agent-detect.sh; printf "%s" "${AGENT_SHELL:-}"'
)
[ "$detected" = codex ] || fail "Codex session did not select the agent credential seam"

echo "agent-detect: all checks passed"
