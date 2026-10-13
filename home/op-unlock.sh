# Body of op-unlock. Interpolated into home/mac-mini.nix after
# `signin_exp=<op-signin-pty.exp>`; run by tests/op-unlock.sh with stubs.
# Expects op, launchctl, expect and ssh on PATH.
state="$HOME/.local/state/op"
f="$state/personal-session"
job=com.alexmiller.op-unlock
# Only the user session counts here: op lets an inherited service-account or
# Connect credential answer every call, which made a dead window look open.
unset OP_SERVICE_ACCOUNT_TOKEN OP_CONNECT_HOST OP_CONNECT_TOKEN

# vault list, not whoami: a server round trip that also resets the 30-minute idle timer.
alive() { [ -r "$f" ] && op --session "$(cat "$f")" vault list >/dev/null 2>&1; }

start_window() { # <hours>: replace any running window with the token in $f.tmp
  launchctl remove "$job" >/dev/null 2>&1 || true
  mv "$f.tmp" "$f"
  # Transient launchd job, not screen/nohup: macOS kills those with the ssh
  # session that started them (the phone terminal closing).
  launchctl submit -l "$job" -- "$0" keepalive "$1"
}

case "${1:-}" in
  keepalive) # internal: op-unlock keepalive <hours>
    end=$(( $(date +%s) + ${2:-24} * 3600 ))
    why=deadline
    while [ "$(date +%s)" -lt "$end" ] && [ -r "$f" ]; do
      sleep 600
      # One failed check is usually the network; retries stay well inside
      # the 30-minute idle limit.
      tries=0
      until err=$(op --session "$(cat "$f" 2>/dev/null)" vault list 2>&1 >/dev/null); do
        tries=$((tries + 1))
        if [ "$tries" -ge 5 ]; then why="session check failed: $(printf '%s' "$err" | tail -n 1)"; break 2; fi
        sleep 60
      done
    done
    echo "$(date '+%F %T') window ended: $why" >> "$state/op-unlock.log"
    if [ -r "$f" ]; then op --session "$(cat "$f")" signout >/dev/null 2>&1 || true; fi
    rm -f "$f"
    # submit jobs restart on exit; remove this one so it ends here
    launchctl remove "$job" >/dev/null 2>&1 || true
    ;;
  lock)
    launchctl remove "$job" >/dev/null 2>&1 || true
    if [ -r "$f" ]; then
      op --session "$(cat "$f")" signout >/dev/null 2>&1 || true
      rm -f "$f"; echo "locked"
    else
      echo "already locked"
    fi
    ;;
  status) # report only: the keepalive owns ending a window
    if alive; then echo "unlocked (session file $(stat -f %Sm "$f"))"; else echo "locked"; fi
    ;;
  --stdin) # password on stdin (the laptop's Hammerspoon prompt), hours as $2
    hours="${2:-24}"
    umask 077; mkdir -p "$state"
    IFS= read -r pw || true
    if ! OP_BIN="$(command -v op)" OP_PW="$pw" expect -f "$signin_exp" > "$f.tmp"; then
      rm -f "$f.tmp"; unset pw; exit 1
    fi
    unset pw
    start_window "$hours"
    echo "unlocked for ${hours}h"
    ;;
  request) # ask the owner, on the laptop, to open a window
    if alive; then echo "already unlocked"; exit 0; fi
    reason=$(printf '%s' "${2:-an agent needs a vault outside AI Agent}" | tr -c 'A-Za-z0-9 ._:/()-' ' ' | cut -c1-160)
    # A watched file, not `hs -c`: an hs client spawned from an ssh
    # session wedges Hammerspoon's IPC port (opUnlock.lua watches the dir).
    if AGENT_SHELL="${AGENT_SHELL:-claude}" ssh -o BatchMode=yes -o ConnectTimeout=5 macbook-air-tailscale \
        "mkdir -p ~/.local/state/op-unlock && printf '%s' '$reason' > ~/.local/state/op-unlock/request" >/dev/null 2>&1; then
      echo "asked on the laptop; run op-unlock status when the vault is next needed"
    else
      echo "laptop unreachable: ask the owner to run op-unlock from their phone"
    fi
    ;;
  ""|[0-9]*)
    hours="${1:-24}"
    umask 077; mkdir -p "$state"
    # Prompts for the account password on this tty; --raw prints the token.
    op signin --raw > "$f.tmp" || { rm -f "$f.tmp"; exit 1; }
    start_window "$hours"
    echo "unlocked for ${hours}h - agents can read Personal via op-personal; op-unlock lock to end early"
    ;;
  *)
    echo "usage: op-unlock [hours=24] | --stdin [hours] | request \"<reason>\" | lock | status" >&2
    exit 1
    ;;
esac
