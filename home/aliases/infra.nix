# Personal-infrastructure aliases — Alex's machines/filesystem layout only.
# A work host should NOT import this file.
{
  programs.zsh.shellAliases = {
    coding = "cd ~/Desktop/coding";
    projects = "cd ~/Desktop/coding/active-projects";
    inactive-projects = "cd ~/Desktop/coding/inactive-projects";
    reference-repos = "cd ~/Desktop/coding/reference-repos";

    # /etc/nix-darwin is the canonical path to the nix-config clone (declared
    # in hosts/macbook-air.nix) — these survive the clone moving again.
    switch-laptop = "just --justfile /etc/nix-darwin/justfile switch-laptop";
    redeploy-mac-mini-config = "just --justfile /etc/nix-darwin/justfile deploy";

    # alias/function source now lives in nix-config (rebuild to apply edits)
    valiases = "nvim /etc/nix-darwin/home/aliases";
    vfuncs = "nvim /etc/nix-darwin/home/zsh/functions.zsh";
    caliases = "alias | sort";
    cfuncs = "cat /etc/nix-darwin/home/zsh/functions.zsh";
  };
}
