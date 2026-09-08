{ pkgs, ... }:

# spotify-player (TUI + scripting CLI, binary: spotify_player) via the native
# HM module - package + ~/.config/spotify-player/app.toml in one place.
# Laptop-personal: a music player has no place in the work-exportable list.
# Option docs: https://github.com/aome510/spotify-player/blob/master/docs/config.md
#
# The binary on PATH is an op-authed wrapper (same family as op-wrappers.nix;
# the raw package stays out of home.packages so PATH order can't bypass it).
# spotify_player's whole auth state is one file, credentials.json (a librespot
# reusable-credentials blob, account-bound, not machine-bound), so the wrapper
# keeps it in the "AI Agent Spotify Player Credentials" item and hands it to
# the binary via a per-invocation mktemp cache folder (-C) that is removed on
# exit - nothing credential-shaped persists, and every machine is authed the
# moment the item is. If the run changes the blob (a first
# `spotify_player authenticate`, or librespot rotating it) the wrapper writes
# it back, so `authenticate` through the wrapper IS the one-time bootstrap -
# no per-machine step. The persistent cache dir bought nothing here
# (cover_img_length = 0, audio_cache = false). Caller-set -C/--cache-folder
# bypasses the round-trip.
# ponytail: -d (daemon) would lose the tmp cache when the parent exits; no
# daemon is declared today - give it a persistent -C if one ever is.
let
  vault = "4eeyrkqibibn7k4j6rz2fbzvxm"; # AI Agent
  item = "et2pkys6ffiobdbjshnz3xenpy"; # AI Agent Spotify Player Credentials
  wrapped = pkgs.writeShellApplication {
    name = "spotify_player";
    runtimeInputs = [
      pkgs._1password-cli
      pkgs.coreutils
    ];
    text = ''
      for a in "$@"; do
        case "$a" in
          -C | --cache-folder | --cache-folder=*) exec ${pkgs.spotify-player}/bin/spotify_player "$@" ;;
        esac
      done
      ${builtins.readFile ./agent-detect.sh}
      ${builtins.readFile ./agent-op-env.sh}
      cache="$(mktemp -d "''${TMPDIR:-/tmp}/spotify-player-XXXXXX")"
      trap 'rm -rf "$cache"' EXIT
      creds="$cache/credentials.json"
      if [ -n "''${OP_SERVICE_ACCOUNT_TOKEN:-}" ] || [ -n "$(op account list 2>/dev/null)" ]; then
        op read 'op://${vault}/${item}/credential' > "$creds" 2>/dev/null || true
      fi
      # Placeholder (CHANGEME) or unreadable → start unauthenticated; the
      # binary then says so, or `authenticate` mints a blob we write back.
      if ! grep -q auth_data "$creds" 2>/dev/null; then rm -f "$creds"; fi
      before="$( { [ -f "$creds" ] && sha256sum "$creds"; } | cut -d' ' -f1 || true)"
      set +e
      ${pkgs.spotify-player}/bin/spotify_player -C "$cache" "$@"
      rc=$?
      set -e
      if [ -s "$creds" ] && [ "$(sha256sum "$creds" | cut -d' ' -f1)" != "$before" ]; then
        if ! op item edit ${item} --vault ${vault} "credential[concealed]=$(cat "$creds")" >/dev/null 2>&1; then
          echo "spotify_player wrapper: WARNING - credentials changed but could not be written back to 1Password (op unauthenticated or rate-limited?); this machine will be unauthenticated again next run" >&2
        fi
      fi
      exit "$rc"
    '';
  };
in
{
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
