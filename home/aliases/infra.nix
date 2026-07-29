# Personal-infrastructure aliases — Alex's machines/filesystem layout only.
# A work host should NOT import this file.
{
  programs.zsh.shellAliases = {
    coding = "cd ~/Desktop/coding";
    projects = "cd ~/Desktop/coding/active-projects";
    inactive-projects = "cd ~/Desktop/coding/inactive-projects";
    reference-repos = "cd ~/Desktop/coding/reference-repos";
    redeploy-mac-mini-config = "just --justfile ~/Desktop/coding/active-projects/nix-config/justfile deploy";

    # alias/function source now lives in nix-config (rebuild to apply edits)
    valiases = "nvim ~/Desktop/coding/active-projects/nix-config/home/aliases";
    vfuncs = "nvim ~/Desktop/coding/active-projects/nix-config/home/zsh/functions.zsh";
    caliases = "alias | sort";
    cfuncs = "cat ~/Desktop/coding/active-projects/nix-config/home/zsh/functions.zsh";
  };
}
