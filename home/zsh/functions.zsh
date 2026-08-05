just() {
  if [ $# -eq 0 ]; then
    command just --list
  else
    command just "$@"
  fi
}
modal() {
  # Modal creds live in 1Password ("AI Agent Modal Token"), not ~/.modal.toml.
  # Env vars override the (deleted) toml; works in desktop shells and Claude SA shells.
  # Inside a uv project use its venv's modal; otherwise uvx.
  local d=$PWD runner=(uvx modal)
  while [[ $d != / ]]; do
    [[ -f $d/pyproject.toml ]] && { runner=(uv run modal); break }
    d=${d:h}
  done
  MODAL_TOKEN_ID="$(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/2sfxybjpv3c3ohzxhf5qeken4a/token_id')" \
  MODAL_TOKEN_SECRET="$(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/2sfxybjpv3c3ohzxhf5qeken4a/token_secret')" \
  "${runner[@]}" "$@"
}
code() {
  # A lone existing .md file goes through the macOS open path so
  # editorAssociations applies (Milkdown); the CLI path forces the text editor.
  if [[ $# -eq 1 && "$1" == *.md && -f "$1" ]]; then
    open -a "Visual Studio Code" "$1"
  else
    command code "$@"
  fi
}
