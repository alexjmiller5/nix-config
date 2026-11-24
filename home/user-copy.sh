#!/usr/bin/env bash
set -euo pipefail
if [[ $# -gt 0 ]]; then
  echo 'Usage: user-copy < file  (or pipe text on stdin)' >&2
  [[ $# -eq 1 && "$1" == '--help' ]] && exit 0
  exit 2
fi
if [[ -t 0 ]]; then
  echo 'user-copy: pipe text on stdin or redirect a file' >&2
  exit 2
fi
target="${USER_CLIPBOARD_HOST:-local}"
if [[ "$target" == local ]]; then
  exec pbcopy
fi
if [[ ! "$target" =~ ^[[:alnum:]][[:alnum:]_.@-]*$ ]]; then
  echo 'user-copy: invalid clipboard SSH host' >&2
  exit 2
fi
exec ssh -T -o BatchMode=yes -o ConnectTimeout=5 "$target" /usr/bin/pbcopy
