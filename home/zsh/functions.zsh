notiondbprops() {
  curl "https://api.notion.com/v1/databases/$1" \
    -H "Authorization: Bearer $(op item get 'SYNAPSE_NOTION_INTERNAL_INTEGRATION_SECRET' --fields credential --reveal)" \
    -H "Notion-Version: 2022-06-28"
}
crpath() {
  if [ -z "$1" ]; then
    # No argument: copy current working directory
    pwd | tr -d '\n' | pbcopy
    echo "Current directory copied to clipboard."
  else
    # Argument provided: resolve absolute path of the file/dir
    if [ -f "$1" ] || [ -d "$1" ]; then
      # Compatible with macOS/Linux without requiring 'realpath'
      echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")" | tr -d '\n' | pbcopy
      echo "Path to '$1' copied to clipboard."
    else
      echo "Error: '$1' does not exist."
    fi
  fi
}
bundleid() {
  osascript -e "id of app \"$1\""
}
ytdlp-gif() {
    if [[ -z "$1" ]]; then
        echo "Usage: yt2gif <url>"
        return 1
    fi

    local url="$1"
    local tmpdir
    tmpdir="$(mktemp -d /tmp/yt2gif_XXXXXX)"
    local tmpvid="${tmpdir}/vid.mp4"

    echo "Downloading video..."
    yt-dlp -f 'bv[vcodec^=avc]+ba/b[vcodec^=avc]' --merge-output-format mp4 -o "$tmpvid" "$url" || { rm -rf "$tmpdir"; return 1; }

    local title
    title="$(yt-dlp --print '%(title)s' --no-download "$url" | tr ' ' '_' | tr -cd '[:alnum:]_-')"
    local outfile="${title}.gif"

    echo "Converting to GIF..."
    ffmpeg -y -i "$tmpvid" \
        -vf "split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
        "$outfile" || { rm -rf "$tmpdir"; return 1; }

    rm -rf "$tmpdir"
    echo "Saved: $outfile"
}
encrypt-folder() {
    local src="$1"
    local dest="$2"

    if [[ ! -d "$src" ]]; then
        echo "Error: Source directory '$src' does not exist."
        return 1
    fi

    # Creates encrypted sparse bundle
    # -volname is auto-set to the source folder's name
    hdiutil create -srcfolder "$src" \
                   -encryption AES-256 \
                   -format UDSB \
                   -volname "$(basename "$src")" \
                   "$dest"
}
just() {
  if [ $# -eq 0 ]; then
    command just --list
  else
    command just "$@"
  fi
}
scpfrom() {
  # scpfrom <ssh-host-alias> <remote-path> [local-dest]
  # Uses your ~/.ssh/config Host aliases, so scp resolves hostname/user for you.
  if [[ -z "$1" || -z "$2" ]]; then
    echo "Usage: scpfrom <ssh-host-alias> <remote-path> [local-dest]"
    return 1
  fi
  scp -r "$1:$2" "${3:-.}"
}
copy-file-contents() {
  # cat a file's contents onto the clipboard
  if [[ ! -f "$1" ]]; then
    echo "Usage: copy-file-contents <file>"
    return 1
  fi
  pbcopy < "$1" && echo "Copied contents of '$1' to clipboard."
}
ftouch() {
  # touch that also creates any missing parent directories, noting when it does
  if [[ -z "$1" ]]; then
    echo "Usage: ftouch <path>"
    return 1
  fi
  local dir
  dir="$(dirname "$1")"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir" && echo "Created missing directories: $dir"
  fi
  touch "$1"
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
codef() {
  # Open a file in VS Code via deep link (faster than the `code` CLI)
  if [[ -z "$1" ]]; then
    echo "Usage: codef <path>"
    return 1
  fi
  local abs
  abs="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")" || { echo "Path not found: $1"; return 1; }
  /usr/bin/open "vscode://file${abs}"
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