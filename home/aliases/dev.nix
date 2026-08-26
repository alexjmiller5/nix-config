# General development + media aliases — portable to any machine.
{
  # (`..`/`../..` navigation comes from programs.zsh.autocd, not an alias)
  programs.zsh.shellAliases = {
    la = "ls -a";
    lla = "ls -la";
    # (`vim` = programs.neovim.vimAlias — a real shim, works outside zsh too)

    # git
    status = "git status";
    commit = "git commit";
    add = "git add -A";
    push = "git push";
    pull = "git pull";
    branch = "git branch";
    log = "git log";
    gundo = "git reset --mixed HEAD~1";

    # gh
    ghperms = "gh repo view --json viewerPermission";
    ghrepo = "gh repo view --web";
    ghprs = "gh pr list --web";
    ghbranch = ''gh browse --branch "$(git branch --show-current)"'';

    # files / clipboard
    # cat with syntax highlighting, otherwise cat-like (no pager, no gutter)
    cat = "bat --paging=never --style=plain";
    copy = "pbcopy <";
    nfiles = "find . -maxdepth 1 -type f | wc -l | tr -d ' '";

    # media
    ytdlp-mp3 = "yt-dlp -x --audio-format mp3 --audio-quality 0 -o '%(title)s.%(ext)s'";
    ytdlp-mp4 = "yt-dlp -f 'bv[vcodec^=avc]+ba/b[vcodec^=avc]' -o '%(title)s.%(ext)s' --merge-output-format mp4";
    mp3play = "ffplay -nodisp -autoexit";
    imgmeta = "exiftool -json -DateTimeOriginal -CreateDate -Make -Model -ImageSize -FileSize -GPSPosition -LensModel -ExposureTime -FNumber -ISO";
  };
}
