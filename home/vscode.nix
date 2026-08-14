{ pkgs, nix-vscode-extensions, ... }:

# VS Code extensions, fully declared (pruned 2026-08-13: dropped unused
# themes/icon packs — settings.json pins GitHub Dark Default + great-icons —
# and retired stacks: Java, Django, Ruby, Go, Azure, Home Assistant,
# Processing, plus superseded duplicates). The app itself stays the
# visual-studio-code cask — package = null installs nothing — but
# home-manager owns ~/.vscode/extensions as an immutable set: VS Code can no
# longer install or update extensions itself. Add/remove = edit this list +
# rebuild; versions ride the weekly nix-vscode-extensions input bump.
# (workspace-snapshot-terminals joins this set via the workspace-snapshot
# flake module — see programs.workspace-snapshot in macbook-air.nix.)
let
  mkt = nix-vscode-extensions.extensions.${pkgs.stdenv.hostPlatform.system}.vscode-marketplace;
in
{
  programs.vscode = {
    enable = true;
    package = null; # app comes from the cask
    profiles.default.extensions = (with mkt; [
      aaron-bond.better-comments
      albert.tabout
      alefragnani.rtf
      alexcvzz.vscode-sqlite
      bbenoist.nix
      bierner.github-markdown-preview
      bierner.markdown-checkbox
      bierner.markdown-emoji
      bierner.markdown-footnotes
      bierner.markdown-mermaid
      bierner.markdown-preview-github-styles
      bierner.markdown-yaml-preamble
      bradlc.vscode-tailwindcss
      charliermarsh.ruff
      christian-kohler.npm-intellisense
      davidanson.vscode-markdownlint
      dbaeumer.vscode-eslint
      dnicolson.binary-plist
      docker.docker
      donjayamanne.githistory
      dorianmassoulier.repomix-runner
      dsznajder.es7-react-js-snippets
      eamodio.gitlens
      ecmel.vscode-html-css
      electrikmilk.cherri-vscode-extension
      emmanuelbeziat.vscode-great-icons
      esbenp.prettier-vscode
      formulahendry.code-runner
      foxundermoon.shell-format
      george-alisson.html-preview-vscode
      github.github-vscode-theme
      github.remotehub
      github.vscode-github-actions
      github.vscode-pull-request-github
      google.gemini-cli-vscode-ide-companion
      hashicorp.terraform
      humao.rest-client
      idleberg.applescript
      idleberg.jxa
      james-yu.latex-workshop
      janisdd.vscode-edit-csv
      jock.svg
      kevinrose.vsc-python-indent
      llvm-vs-code-extensions.lldb-dap
      mads-hartmann.bash-ide-vscode
      mariusalchimavicius.json-to-ts
      mechatroner.rainbow-csv
      meganrogge.template-string-converter
      mgesbert.python-path
      mirone.milkdown
      ms-azuretools.vscode-containers
      ms-python.debugpy
      ms-python.python
      ms-python.vscode-python-envs
      ms-toolsai.jupyter
      ms-toolsai.jupyter-keymap
      ms-toolsai.jupyter-renderers
      ms-toolsai.vscode-jupyter-cell-tags
      ms-toolsai.vscode-jupyter-slideshow
      ms-vscode.cmake-tools
      ms-vscode.cpp-devtools
      ms-vscode.cpptools-extension-pack
      ms-vscode.cpptools-themes
      ms-vscode.extension-test-runner
      ms-vscode.hexeditor
      ms-vscode.live-server
      ms-vscode.makefile-tools
      ms-vscode.remote-repositories
      ms-vscode.remote-server
      mtxr.sqltools
      mtxr.sqltools-driver-pg
      mtxr.sqltools-driver-sqlite
      oderwat.indent-rainbow
      pflannery.vscode-versionlens
      pomdtr.excalidraw-editor
      redhat.vscode-xml
      redhat.vscode-yaml
      repreng.csv
      ryuta46.multi-command
      shardulm94.trailing-spaces
      simonsiefke.svg-preview
      skellock.just
      slevesque.vscode-3dviewer
      sumneko.lua
      svelte.svelte-vscode
      sweetpad.sweetpad
      swiftlang.swift-vscode
      tailscale.vscode-tailscale
      tamasfe.even-better-toml
      timonwong.shellcheck
      tonybaloney.vscode-pets
      twxs.cmake
      usernamehw.errorlens
      vadimcn.vscode-lldb
      virgilsisoe.hammerspoon
      virgilsisoe.hammerspoon-snippets
      xshrim.txt-syntax
      yzhang.markdown-all-in-one
      zignd.html-css-class-completion
    ]) ++ (with pkgs.vscode-extensions; [
      # Platform-specific / licensed builds the marketplace mirror refuses to
      # serve on aarch64-darwin — nixpkgs packages these properly (all unfree;
      # covered by the vscode-extension- prefix in the host's unfree predicate).
      anthropic.claude-code
      ms-python.vscode-pylance
      ms-vscode-remote.remote-containers
      ms-vscode-remote.remote-ssh
      ms-vscode-remote.remote-ssh-edit
      ms-vscode.cpptools
      ms-vscode.remote-explorer
      natqe.reload
    ]);
  };
}
