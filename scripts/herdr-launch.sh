#!/usr/bin/env bash
set -euo pipefail
core=${HERDR_CORE_BIN:-herdr-core}
# New terminals share the native desktop space and persist after detaching.
if [[ ${1:-} == new ]]; then
  shift
  if [[ -z ${HERDR_SPACE_ID:-} ]]; then
    echo 'hdr new needs a configured native desktop space id.' >&2
    exit 2
  fi
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"doc.get","params":{"name":"herdr-app"}}' |
    "$core" connect | "${HERDR_PYTHON_BIN:-python3}" -c '
import json,sys
reply = json.load(sys.stdin)
spaces = ((reply.get("result") or {}).get("value") or {}).get("spaces", [])
if not any(space.get("id") == sys.argv[1] for space in spaces):
    sys.exit("hdr new: configured native desktop space is unavailable.")
' "$HERDR_SPACE_ID"
  terminal=$("$core" run --bg --json --no-parent --no-notify --keep --cwd "$HOME" \
    --label "herdr.space=$HERDR_SPACE_ID" "$@" |
    "${HERDR_PYTHON_BIN:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["address"])')
  exec "$core" attach "$terminal"
fi
menu=false
if [[ ${1:-} == menu ]]; then
  menu=true
  shift
fi
if [[ $# -eq 0 ]]; then
  if [[ -n ${HERDR_APP_BUNDLE:-} && -z ${SSH_CONNECTION:-} && -z ${SSH_TTY:-} ]]; then
    exec open -a "$HERDR_APP_BUNDLE"
  fi
  if [[ ! -t 0 ]]; then
    exec "$core" attach
  fi
  if [[ $menu == false && -n ${HERDR_TUI_BIN:-} ]]; then
    exec "$HERDR_TUI_BIN" --touch
  fi
  while true; do
    printf '\nHerdr sessions\n  s  Select session\n  n  New session\n  q  Quit\nCtrl+Backslash returns here without stopping the session.\n'
    if ! read -r -p 'Choose [s/n/q]: ' choice; then
      exit 0
    fi
    case "$choice" in
      s|S|'') "$core" attach || true ;;
      n|N) "$BASH" "$0" new || true ;;
      q|Q) exit 0 ;;
      *) printf 'Choose s, n, or q.\n' ;;
    esac
  done
fi
exec "$core" "$@"
