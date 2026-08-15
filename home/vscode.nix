{ pkgs, nix-vscode-extensions, ... }:

# VS Code extensions, fully declared and grouped by function (audited
# 2026-08-15: every entry either matches the current stack — Python/uv/ruff,
# Bun/Svelte/Tailwind, Swift/iOS, nix, cherri, hammerspoon, just — or is
# wired into settings.json; unused, deprecated, and superseded extensions
# removed). The app itself stays the visual-studio-code cask — package = null
# installs nothing — but home-manager owns ~/.vscode/extensions as an
# immutable set: VS Code can no longer install or update extensions itself.
# Add/remove = edit this list + rebuild; versions ride the weekly
# nix-vscode-extensions input bump. (workspace-snapshot-terminals joins this
# set via the workspace-snapshot flake module — see
# programs.workspace-snapshot in macbook-air.nix.)
let
  mkt = nix-vscode-extensions.extensions.${pkgs.stdenv.hostPlatform.system}.vscode-marketplace;
in
{
  programs.vscode = {
    enable = true;
    package = null; # app comes from the cask
    profiles.default.extensions = (with mkt; [
      # --- Theme + icons (the pair settings.json pins) ---
      github.github-vscode-theme
      emmanuelbeziat.vscode-great-icons

      # --- AI assistants (claude-code comes from nixpkgs below) ---
      google.gemini-cli-vscode-ide-companion

      # --- Editor QoL ---
      aaron-bond.better-comments
      albert.tabout
      formulahendry.code-runner # executorMap configured in settings.json
      meganrogge.template-string-converter
      oderwat.indent-rainbow
      shardulm94.trailing-spaces
      usernamehw.errorlens
      tonybaloney.vscode-pets # fun

      # --- Git + GitHub ---
      eamodio.gitlens
      github.remotehub
      github.vscode-github-actions
      github.vscode-pull-request-github
      ms-vscode.remote-repositories

      # --- Remote dev (remote-ssh family comes from nixpkgs below) ---
      ms-vscode.remote-server
      tailscale.vscode-tailscale

      # --- Python (uv/ruff stack; pylance comes from nixpkgs below) ---
      charliermarsh.ruff
      kevinrose.vsc-python-indent
      ms-python.debugpy
      ms-python.python
      ms-python.vscode-python-envs
      ms-toolsai.jupyter
      ms-toolsai.jupyter-keymap
      ms-toolsai.jupyter-renderers
      ms-toolsai.vscode-jupyter-cell-tags
      ms-toolsai.vscode-jupyter-slideshow

      # --- Web: JS/TS, Svelte, Tailwind, CSS ---
      bradlc.vscode-tailwindcss
      christian-kohler.npm-intellisense
      dbaeumer.vscode-eslint
      ecmel.vscode-html-css
      esbenp.prettier-vscode
      ms-vscode.live-server
      pflannery.vscode-versionlens # showOnStartup configured in settings.json
      svelte.svelte-vscode

      # --- Swift / iOS ---
      sweetpad.sweetpad
      swiftlang.swift-vscode
      llvm-vs-code-extensions.lldb-dap # debugger for swift-vscode

      # --- C/C++ + build systems (CTF + systems work; cpptools from nixpkgs below) ---
      ms-vscode.cmake-tools
      ms-vscode.cpp-devtools
      ms-vscode.cpptools-extension-pack
      ms-vscode.cpptools-themes
      ms-vscode.makefile-tools
      twxs.cmake
      ms-vscode.hexeditor

      # --- Shell ---
      foxundermoon.shell-format
      mads-hartmann.bash-ide-vscode
      timonwong.shellcheck

      # --- Nix ---
      bbenoist.nix

      # --- macOS automation: AppleScript/JXA, Hammerspoon, Shortcuts ---
      idleberg.applescript
      idleberg.jxa
      virgilsisoe.hammerspoon
      virgilsisoe.hammerspoon-snippets
      sumneko.lua # hammerspoon configs
      dnicolson.binary-plist
      electrikmilk.cherri-vscode-extension

      # --- Markdown ---
      yzhang.markdown-all-in-one
      davidanson.vscode-markdownlint
      bierner.github-markdown-preview # pack: pulls the bierner set below
      bierner.markdown-checkbox
      bierner.markdown-emoji
      bierner.markdown-footnotes
      bierner.markdown-mermaid
      bierner.markdown-preview-github-styles
      bierner.markdown-yaml-preamble
      mirone.milkdown # *.md editorAssociation in settings.json

      # --- Data + file formats ---
      janisdd.vscode-edit-csv
      mechatroner.rainbow-csv
      mtxr.sqltools
      mtxr.sqltools-driver-sqlite
      jock.svg # svg.preview.mode configured in settings.json
      redhat.vscode-xml # *.plist association in settings.json
      redhat.vscode-yaml
      tamasfe.even-better-toml
      humao.rest-client
      pomdtr.excalidraw-editor

      # --- Infra + tooling ---
      docker.docker
      ms-azuretools.vscode-containers # container tools, not Azure
      hashicorp.terraform # OCI VM fleet
      nefrob.vscode-just-syntax
      james-yu.latex-workshop # resume is .tex
      ms-vscode.extension-test-runner # workspace-snapshot extension dev
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
