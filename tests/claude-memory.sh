#!/usr/bin/env bash
# Fixture test for the claude-memory adopt+link loops in home/agents.nix.
#
# The loops move real directories around, so they get a check. The code under
# test is EXTRACTED from agents.nix between its `>>> claude-memory >>>` markers
# rather than copied here — a copy would silently drift from the shipped script.
set -euo pipefail
cd "$(dirname "$0")/.."

block=$(sed -n '/>>> claude-memory/,/<<< claude-memory/p' home/agents.nix \
  | sed -e '1d;$d' -e "s/''\\\${/\${/g")
[ -n "$block" ] || { echo "FAIL: markers not found in home/agents.nix"; exit 1; }
eval "claude_memory() { $block
}"

fail() { echo "FAIL: $1"; exit 1; }

# --- scenario A: adopt, link, collision, empty dir ---
root=$(mktemp -d)
export HOME="$root/home"
mkdir -p "$HOME"/.claude/projects/{-new,-empty,-collide}/memory "$root"/repo/memory/{-collide,-repo-only}
echo "fresh"  > "$HOME/.claude/projects/-new/memory/a.md"
echo "local"  > "$HOME/.claude/projects/-collide/memory/a.md"
echo "repo"   > "$root/repo/memory/-collide/a.md"
echo "remote" > "$root/repo/memory/-repo-only/b.md"

cd "$root/repo"
claude_memory

# a new local dir is adopted into the repo and linked back, readable through the link
[ -f memory/-new/a.md ]                      || fail "new dir not adopted"
[ -L "$HOME/.claude/projects/-new/memory" ]  || fail "adopted dir not linked back"
[ "$(cat "$HOME/.claude/projects/-new/memory/a.md")" = fresh ] || fail "link not readable"

# a repo-only slug is linked out (the fresh-machine case)
[ "$(cat "$HOME/.claude/projects/-repo-only/memory/b.md")" = remote ] || fail "repo-only slug not linked"

# collision: local dir left real and intact, repo copy intact, no junk nested link
[ ! -L "$HOME/.claude/projects/-collide/memory" ] || fail "collision clobbered local dir"
[ "$(cat "$HOME/.claude/projects/-collide/memory/a.md")" = local ] || fail "collision lost local data"
[ "$(cat memory/-collide/a.md)" = repo ]     || fail "collision lost repo data"
[ ! -e "$HOME/.claude/projects/-collide/memory/-collide" ] || fail "junk link nested in local dir"

# an empty local dir is not adopted (git ignores empty dirs anyway)
[ ! -e memory/-empty ]                       || fail "empty dir adopted"

# idempotent: a second run changes nothing
before=$(find memory "$HOME/.claude/projects" | sort)
claude_memory
[ "$(find memory "$HOME/.claude/projects" | sort)" = "$before" ] || fail "not idempotent"

# --- scenario B: empty repo memory/ must not create a literal '*' dir ---
root=$(mktemp -d)
export HOME="$root/home"
mkdir -p "$HOME/.claude/projects" "$root/repo/memory"
cd "$root/repo"
claude_memory
[ ! -e 'memory/*' ] && [ ! -e "$HOME/.claude/projects/*" ] || fail "unmatched glob created a literal dir"

echo "claude-memory: all checks passed"
