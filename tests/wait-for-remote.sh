#!/usr/bin/env bash
# Fixture test for the wait-for-remote loop in home/agents.nix.
#
# The loop decides whether the sync proceeds or bails, and it burns wall-clock
# doing it, so it gets a check. Same extraction trick as claude-memory.sh: the
# code under test comes out of agents.nix between its markers, never a copy.
set -euo pipefail
cd "$(dirname "$0")/.."

block=$(sed -n '/>>> wait-for-remote/,/<<< wait-for-remote/p' home/agents.nix \
  | sed -e '1d;$d' -e "s/''\\\${/\${/g")
[ -n "$block" ] || { echo "FAIL: markers not found in home/agents.nix"; exit 1; }

fail() { echo "FAIL: $1"; exit 1; }

# Runs the block with git going online after $1 failed probes (999 = never).
# Echoes the number of sleeps it took; exit status is the block's own.
run() (
  set -euo pipefail
  online_after=$1 probes=0 slept=0
  git() { probes=$((probes + 1)); [ "$probes" -gt "$online_after" ]; }
  sleep() { slept=$((slept + 1)); }
  eval "$block"
  echo "$slept"
)

# already online: no waiting at all, block continues (exit 0 from the echo)
[ "$(run 0)" = 0 ] || fail "slept despite being online"

# offline for the first 3 probes: waits, then proceeds
[ "$(run 3)" = 3 ] || fail "wrong sleep count while waiting for the network"

# never online: gives up quietly (exit 0, no notification path) after 60 probes
out=$(run 999) || fail "give-up path exited nonzero — would look like a conflict"
[ -z "$out" ] || fail "give-up path fell through to the sync instead of exiting"

echo "wait-for-remote: all checks passed"
