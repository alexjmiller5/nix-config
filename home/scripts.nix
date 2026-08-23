{ pkgs, ... }:

# Standalone commands, packaged (shellcheck at build, deps pinned, on PATH in
# every context — launchd, Raycast, agent shells). Shell-state functions and
# command shadows that need shell state (just, code) stay in zsh/functions.zsh;
# only real tiny-programs live here. Shared by both hosts.
let
  script = name: args: pkgs.writeShellApplication ({ inherit name; } // args);
in
{
  home.packages = [
    # Notion data-source schema (2026-03-11 API; the old /v1/databases/ query
    # endpoint is dead). Token = AI Agent integration, by 1P IDs.
    (script "notiondbprops" {
      text = ''
        [ $# -eq 1 ] || { echo "Usage: notiondbprops <data-source-id>"; exit 1; }
        curl -s "https://api.notion.com/v1/data_sources/$1" \
          -H "Authorization: Bearer $(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/nhsh73sfidj4cdowvbaayaq7tq/credential')" \
          -H "Notion-Version: 2026-03-11"
      '';
    })

    # gh, ALWAYS authed via 1Password (PAT item in the AI Agent vault) — the
    # keyring is not used. PATH-level shadow (not an alias/function) so
    # scripts, launchd, and agent shells get auth too.
    # gh must not be installed anywhere else (brew/nix) or PATH order decides.
    (script "gh" {
      runtimeInputs = [ pkgs._1password-cli ];
      text = ''
        if [ -z "''${GH_TOKEN:-}''${GITHUB_TOKEN:-}" ]; then
          ${builtins.readFile ./agent-op-env.sh}
          # SA token → headless; otherwise desktop-app auth (Touch ID).
          # No auth source at all (the mini): skip — op read would prompt
          # "add an account?" on /dev/tty and hang/garble headless callers.
          if [ -n "''${OP_SERVICE_ACCOUNT_TOKEN:-}" ] || [ -n "$(op account list 2>/dev/null)" ]; then
            GH_TOKEN="$(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/spmkea5afgjzcekuahclmwowxq/token' 2>/dev/null || true)"
            if [ -n "$GH_TOKEN" ]; then export GH_TOKEN; fi
          fi
        fi
        exec ${pkgs.gh}/bin/gh "$@"
      '';
    })

    # modal, ALWAYS authed via 1Password (AI Agent vault) — ~/.modal.toml is
    # never written. PATH-level shadow, not a zsh function, so justfiles,
    # scripts, launchd and agent shells get auth too (a function is invisible
    # to all of them). Inside a uv project the project's pinned modal wins;
    # the sentinel stops `uv run modal` re-entering this wrapper when the
    # project has no modal dependency.
    (script "modal" {
      runtimeInputs = [ pkgs._1password-cli pkgs.uv ];
      text = ''
        if [ -z "''${MODAL_TOKEN_ID:-}" ]; then
          ${builtins.readFile ./agent-op-env.sh}
          if [ -n "''${OP_SERVICE_ACCOUNT_TOKEN:-}" ] || [ -n "$(op account list 2>/dev/null)" ]; then
            MODAL_TOKEN_ID="$(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/2sfxybjpv3c3ohzxhf5qeken4a/token_id' 2>/dev/null || true)"
            MODAL_TOKEN_SECRET="$(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/2sfxybjpv3c3ohzxhf5qeken4a/token_secret' 2>/dev/null || true)"
            if [ -n "$MODAL_TOKEN_ID" ] && [ -n "$MODAL_TOKEN_SECRET" ]; then
              export MODAL_TOKEN_ID MODAL_TOKEN_SECRET
            fi
          fi
        fi
        in_uv_project=0
        d=$PWD
        while [ "$d" != "/" ]; do
          if [ -f "$d/pyproject.toml" ]; then in_uv_project=1; break; fi
          d=$(dirname "$d")
        done
        if [ "$in_uv_project" = 0 ] || [ -n "''${_MODAL_WRAPPED:-}" ]; then
          exec uvx modal "$@"
        fi
        export _MODAL_WRAPPED=1
        exec uv run modal "$@"
      '';
    })

    # Copy an absolute path (or cwd) to the clipboard.
    (script "crpath" {
      text = ''
        if [ $# -eq 0 ]; then
          pwd | tr -d '\n' | /usr/bin/pbcopy
          echo "Current directory copied to clipboard."
        elif [ -e "$1" ]; then
          echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")" | tr -d '\n' | /usr/bin/pbcopy
          echo "Path to '$1' copied to clipboard."
        else
          echo "Error: '$1' does not exist."
          exit 1
        fi
      '';
    })

    (script "bundleid" {
      text = ''
        [ $# -eq 1 ] || { echo "Usage: bundleid <app-name>"; exit 1; }
        /usr/bin/osascript -e "id of app \"$1\""
      '';
    })

    # Download a video and convert it to a palette-optimized GIF in cwd.
    (script "ytdlp-gif" {
      runtimeInputs = [ pkgs.yt-dlp pkgs.ffmpeg ];
      text = ''
        [ $# -eq 1 ] || { echo "Usage: ytdlp-gif <url>"; exit 1; }
        url="$1"
        tmpdir="$(mktemp -d "''${TMPDIR:-/tmp}/yt2gif_XXXXXX")"
        trap 'rm -rf "$tmpdir"' EXIT
        tmpvid="$tmpdir/vid.mp4"

        echo "Downloading video..."
        yt-dlp -f 'bv[vcodec^=avc]+ba/b[vcodec^=avc]' --merge-output-format mp4 -o "$tmpvid" "$url"

        title="$(yt-dlp --print '%(title)s' --no-download "$url" | tr ' ' '_' | tr -cd '[:alnum:]_-')"
        outfile="$title.gif"

        echo "Converting to GIF..."
        ffmpeg -y -i "$tmpvid" \
          -vf "split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
          "$outfile"
        echo "Saved: $outfile"
      '';
    })

    # Encrypted AES-256 sparse bundle from a folder.
    (script "encrypt-folder" {
      text = ''
        [ $# -eq 2 ] || { echo "Usage: encrypt-folder <src-dir> <dest>"; exit 1; }
        [ -d "$1" ] || { echo "Error: Source directory '$1' does not exist."; exit 1; }
        /usr/bin/hdiutil create -srcfolder "$1" \
          -encryption AES-256 \
          -format UDSB \
          -volname "$(basename "$1")" \
          "$2"
      '';
    })

    # scp -r via ~/.ssh/config host aliases.
    (script "scpfrom" {
      text = ''
        [ $# -ge 2 ] || { echo "Usage: scpfrom <ssh-host-alias> <remote-path> [local-dest]"; exit 1; }
        scp -r "$1:$2" "''${3:-.}"
      '';
    })

    (script "copy-file-contents" {
      text = ''
        [ $# -eq 1 ] && [ -f "$1" ] || { echo "Usage: copy-file-contents <file>"; exit 1; }
        /usr/bin/pbcopy < "$1" && echo "Copied contents of '$1' to clipboard."
      '';
    })

    # touch that creates missing parent directories.
    (script "ftouch" {
      text = ''
        [ $# -eq 1 ] || { echo "Usage: ftouch <path>"; exit 1; }
        dir="$(dirname "$1")"
        if [ ! -d "$dir" ]; then
          mkdir -p "$dir" && echo "Created missing directories: $dir"
        fi
        touch "$1"
      '';
    })

    # Open a file in VS Code via deep link (faster than the `code` CLI).
    (script "codef" {
      text = ''
        [ $# -eq 1 ] || { echo "Usage: codef <path>"; exit 1; }
        abs="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")" \
          || { echo "Path not found: $1"; exit 1; }
        /usr/bin/open "vscode://file$abs"
      '';
    })
  ];
}
