{ config, pkgs, ... }:

# spotify-player (TUI + scripting CLI, binary: spotify_player) via the native
# HM module - package + ~/.config/spotify-player/app.toml in one place.
# Laptop-personal: a music player has no place in the work-exportable list.
# Option docs: https://github.com/aome510/spotify-player/blob/master/docs/config.md
#
# Built from upstream master (nixpkgs' release lacks the custom-client
# fallback): the Web API uses Alex's own dev app ("AI Agent Spotify OAuth
# Client" item, redirect URI http://127.0.0.1:8989/login registered in the
# Spotify developer dashboard), passed as `-o client_id=`; requests that app
# can't serve (4xx, or the ncspot_only_get_endpoints list) fall back to the
# binary's default ncspot client. ncspot alone is Spotify-throttled for hours
# at a time (429 on every call), a fresh dev app alone loses fields that
# newer apps don't get - master's fallback is what makes either usable.
#
# The binary on PATH is an op-authed wrapper (same family as op-wrappers.nix;
# the raw package stays out of home.packages so PATH order can't bypass it).
# spotify_player's whole auth state is a few cache files, all account-bound
# (not machine-bound): credentials.json (librespot reusable credentials,
# written only when the app connects a session - TUI, never `authenticate`)
# and one <client_id>_token.json per Web API client (OAuth token + refresh
# token, rewritten on each ~hourly refresh). The wrapper keeps them in the
# "AI Agent Spotify Player Credentials" item (field `credential` =
# credentials.json, field `token` = JSON map of token filename → content),
# hands them to the binary via a per-invocation mktemp cache folder (-C)
# removed on exit - nothing credential-shaped persists, every machine is
# authed the moment the item is - and writes back whatever the run changed
# (a token refresh, a login), so `spotify_player authenticate` / a TUI login
# through the wrapper IS the bootstrap. The persistent cache dir bought
# nothing here (cover_img_length = 0, audio_cache = false). Caller-set
# -C/--cache-folder bypasses the round-trip.
# ponytail: -d (daemon) forks and would lose the tmp cache when the parent
# exits; no daemon is declared today - give it a persistent -C if one ever is.
let
  vault = "4eeyrkqibibn7k4j6rz2fbzvxm"; # AI Agent
  item = "et2pkys6ffiobdbjshnz3xenpy"; # AI Agent Spotify Player Credentials
  clientItem = "2gtd2wehp4iqhzhcswyvjiwlvu"; # AI Agent Spotify OAuth Client
  spotify-player = pkgs.spotify-player.overrideAttrs (
    old:
    let
      src = pkgs.fetchFromGitHub {
        owner = "aome510";
        repo = "spotify-player";
        rev = "37a3d8629b4afc864a878412d9c0b9b0bd509a5f";
        hash = "sha256-GfvqNgQmlIohsTkmuxoDQMg0Tz9/tnGb7n0D9liI1ZM=";
      };
    in
    {
      version = "0.24.1-unstable-2026-09-08";
      inherit src;
      cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
        inherit src;
        hash = "sha256-N93J3Z7AAnDSjJBoaKU73rcDZX44Q+BDGiTBuWefwl8=";
      };
    }
  );
  wrapped = pkgs.writeShellApplication {
    name = "spotify_player";
    runtimeInputs = [
      config.opConnect.cliPackage
      pkgs.jq
      pkgs.coreutils
    ];
    text = ''
      for a in "$@"; do
        case "$a" in
          -C | --cache-folder | --cache-folder=*) exec ${spotify-player}/bin/spotify_player "$@" ;;
        esac
      done
      ${builtins.readFile ./agent-detect.sh}
      ${builtins.readFile ./agent-op-env.sh}
      cache="$(mktemp -d "''${TMPDIR:-/tmp}/spotify-player-XXXXXX")"
      trap 'rm -rf "$cache"' EXIT
      creds="$cache/credentials.json"
      cid=""
      if op_has_auth; then
        item="$(op item get ${item} --vault ${vault} --format json)"
        cid="$(op read 'op://${vault}/${clientItem}/client_id')"
        jq -r '[.fields[] | select(.label == "credential")][0].value // empty' <<<"$item" > "$creds"
        tokens="$(jq -r '[.fields[] | select(.label == "token")][0].value // empty' <<<"$item")"
        if jq -e 'type == "object" and (to_entries | all(.value | type == "string"))' <<<"$tokens" >/dev/null 2>&1; then
          for f in $(jq -r 'keys[]' <<<"$tokens"); do
            case "$f" in *_token.json) jq -r --arg k "$f" '.[$k]' <<<"$tokens" > "$cache/$f" ;; esac
          done
        fi
      fi
      # Placeholder (CHANGEME) or unreadable → start without that file; the
      # binary then errors (CLI) or logs in interactively (TUI/authenticate)
      # and we write back whatever it minted.
      grep -q auth_data "$creds" 2>/dev/null || rm -f "$creds"
      state() {
        (cd "$cache" && for f in credentials.json *_token.json; do
          if [ -f "$f" ]; then printf '%s\n' "$f"; cat "$f"; fi
        done 2>/dev/null) | sha256sum | cut -d' ' -f1
      }
      before="$(state)"
      opts=()
      if [ -n "$cid" ]; then opts+=(-o "client_id=$cid"); fi
      set +e
      ${spotify-player}/bin/spotify_player -C "$cache" "''${opts[@]}" "$@"
      rc=$?
      set -e
      if [ "$(state)" != "$before" ]; then
        edits=()
        if [ -s "$creds" ]; then edits+=("credential[concealed]=$(cat "$creds")"); fi
        map='{}'
        for f in "$cache"/*_token.json; do
          if [ -s "$f" ]; then map="$(jq --arg k "$(basename "$f")" --rawfile v "$f" '.[$k] = $v' <<<"$map")"; fi
        done
        if [ "$map" != '{}' ]; then edits+=("token[concealed]=$map"); fi
        if [ "''${#edits[@]}" -gt 0 ] && ! op item edit ${item} --vault ${vault} "''${edits[@]}" >/dev/null 2>&1; then
          echo "spotify_player wrapper: WARNING - credentials changed but could not be written back to 1Password (op unauthenticated or rate-limited?); the change is lost with this run's cache" >&2
        fi
      fi
      exit "$rc"
    '';
  };
in
{
  imports = [ ./op-connect.nix ];
  programs.spotify-player = {
    enable = true;
    package = wrapped;

    settings = {
      theme = "dracula";
      client_port = 8080;
      playback_format = ''
        {status} {track} • {artists} {liked}
        {album} • {genres}
        {metadata}'';
      playback_metadata_fields = [
        "repeat"
        "shuffle"
        "volume"
        "device"
      ];
      notify_timeout_in_secs = 0;
      tracks_playback_limit = 50;
      app_refresh_duration_in_ms = 32;
      playback_refresh_duration_in_ms = 0;
      page_size_in_rows = 20;
      play_icon = "▶";
      pause_icon = "▌▌";
      liked_icon = "♥";
      explicit_icon = "(E)";
      border_type = "Plain";
      progress_bar_type = "Rectangle";
      progress_bar_position = "Bottom";
      genre_num = 2;
      cover_img_length = 0;
      cover_img_width = 5;
      enable_media_control = false;
      enable_streaming = "Always";
      enable_audio_visualization = false;
      enable_notify = true;
      enable_cover_image_cache = true;
      notify_streaming_only = false;
      seek_duration_secs = 5;
      sort_artist_albums_by_type = false;
      volume_scroll_step = 5;
      enable_mouse_scroll_volume = true;
      custom_queue = true;
      enable_relative_line_number = false;
      pause_on_startup = false;

      notify_format = {
        summary = "{track} • {artists}";
        body = "{album}";
      };

      layout = {
        playback_window_position = "Top";
        playback_window_height = 6;
        library = {
          playlist_percent = 40;
          album_percent = 40;
        };
      };

      device = {
        name = "spotify-player";
        device_type = "speaker";
        volume = 70;
        bitrate = 320;
        audio_cache = false;
        normalization = false;
        autoplay = false;
      };
    };
  };
}
