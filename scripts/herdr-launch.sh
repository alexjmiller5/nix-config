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
if [[ $# -eq 0 ]]; then
  if [[ -n ${HERDR_APP_BUNDLE:-} && -z ${SSH_CONNECTION:-} && -z ${SSH_TTY:-} ]]; then
    exec open -a "$HERDR_APP_BUNDLE"
  fi
  exec "$core" attach
fi
exec "$core" "$@"
