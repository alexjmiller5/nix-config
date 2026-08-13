{ ... }:

# spotify-player (TUI + scripting CLI, binary: spotify_player) via the native
# HM module — package + ~/.config/spotify-player/app.toml in one place.
# Laptop-personal: a music player has no place in the work-exportable list.
# Option docs: https://github.com/aome510/spotify-player/blob/master/docs/config.md
{
  programs.spotify-player = {
    enable = true;

    settings = {
      theme = "dracula";
      client_id = "d420a117a32841c2b3474932e49fb54b";
      client_port = 8080;
      login_redirect_uri = "http://127.0.0.1:8989/login";
      playback_format = ''
        {status} {track} • {artists} {liked}
        {album} • {genres}
        {metadata}'';
      playback_metadata_fields = [ "repeat" "shuffle" "volume" "device" ];
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
