{ pkgs, nix-vscode-extensions, workspace-snapshot, ... }:

# VS Code extensions, fully declared (snapshot 2026-08-11). The app itself
# stays the visual-studio-code cask — package = null installs nothing — but
# home-manager owns ~/.vscode/extensions as an immutable set: VS Code can no
# longer install or update extensions itself. Add/remove = edit this list +
# rebuild; versions ride the weekly nix-vscode-extensions input bump.
let
  mkt = nix-vscode-extensions.extensions.${pkgs.stdenv.hostPlatform.system}.vscode-marketplace;
  # Own unpublished extension, built from the workspace-snapshot flake input
  # (dist/ is gitignored upstream — tsc compile; deps are devDependencies only).
  # npmDepsHash tracks vscode-extension/package-lock.json: re-prefetch on bump
  # (`nix run nixpkgs#prefetch-npm-deps -- <input>/vscode-extension/package-lock.json`).
  workspace-snapshot-terminals = pkgs.buildNpmPackage {
    pname = "workspace-snapshot-terminals";
    version = "0.1.0";
    src = "${workspace-snapshot}/vscode-extension";
    npmDepsHash = "sha256-x1iH1g5Ji8s04ORn47lxPtQMsmXlbr8j0BgZlVgyJKQ=";
    npmBuildScript = "compile";
    dontNpmInstall = true;
    installPhase = ''
      runHook preInstall
      dst=$out/share/vscode/extensions/alexmiller.workspace-snapshot-terminals
      mkdir -p "$dst"
      cp -r package.json dist "$dst"/
      runHook postInstall
    '';
  };
in
{
  programs.vscode = {
    enable = true;
    package = null; # app comes from the cask
    profiles.default.extensions = [ workspace-snapshot-terminals ] ++ (with mkt; [
      aaron-bond.better-comments
      albert.tabout
      alefragnani.rtf
      alexandernanberg.horizon-theme-vscode
      alexcvzz.vscode-sqlite
      batisteo.vscode-django
      bbenoist.nix
      be5invis.vscode-icontheme-nomo-dark
      bibhasdn.django-html
      bierner.github-markdown-preview
      bierner.markdown-checkbox
      bierner.markdown-emoji
      bierner.markdown-footnotes
      bierner.markdown-mermaid
      bierner.markdown-preview-github-styles
      bierner.markdown-yaml-preamble
      bradlc.vscode-tailwindcss
      christian-kohler.npm-intellisense
      davidanson.vscode-markdownlint
      davidbabel.antigravity-icons-supercharged-blue
      davidbabel.antigravity-icons-supercharged-gray
      davidbwaters.macos-modern-theme
      dbaeumer.vscode-eslint
      dnicolson.binary-plist
      docker.docker
      donjayamanne.githistory
      dorianmassoulier.repomix-runner
      dsznajder.es7-react-js-snippets
      dustinsanders.an-old-hope-theme-vscode
      eamodio.gitlens
      ecmel.vscode-html-css
      electrikmilk.cherri-vscode-extension
      emmanuelbeziat.vscode-great-icons
      esbenp.prettier-vscode
      file-icons.file-icons
      formulahendry.code-runner
      foxundermoon.shell-format
      george-alisson.html-preview-vscode
      github.github-vscode-theme
      github.remotehub
      github.vscode-github-actions
      github.vscode-pull-request-github
      golang.go
      google.gemini-cli-vscode-ide-companion
      hashicorp.terraform
      helgardrichard.helium-icon-theme
      humao.rest-client
      idleberg.applescript
      idleberg.icon-fonts
      idleberg.jxa
      james-yu.latex-workshop
      jamesmaj.easy-icons
      janisdd.vscode-edit-csv
      jnbt.vscode-rufo
      jock.svg
      junstyle.vscode-django-support
      kaiwood.endwise
      keesschollaart.vscode-home-assistant
      kevinrose.vsc-python-indent
      llvm-vs-code-extensions.lldb-dap
      mads-hartmann.bash-ide-vscode
      mariusalchimavicius.json-to-ts
      mechatroner.rainbow-csv
      meganrogge.template-string-converter
      mgesbert.python-path
      miguelsolorio.symbols
      mirone.milkdown
      monokai.theme-monokai-pro-vscode
      ms-azuretools.vscode-azureresourcegroups
      ms-azuretools.vscode-containers
      ms-azuretools.vscode-docker
      ms-python.black-formatter
      ms-python.debugpy
      ms-python.isort
      ms-python.python
      ms-python.vscode-python-envs
      ms-toolsai.jupyter
      ms-toolsai.jupyter-keymap
      ms-toolsai.jupyter-renderers
      ms-toolsai.vscode-jupyter-cell-tags
      ms-toolsai.vscode-jupyter-slideshow
      ms-vscode.azure-repos
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
      pkief.material-icon-theme
      pkief.material-product-icons
      pomdtr.excalidraw-editor
      prisma.prisma
      redhat.java
      redhat.vscode-xml
      redhat.vscode-yaml
      repreng.csv
      ritwickdey.liveserver
      robbowen.synthwave-vscode
      ryuta46.multi-command
      shardulm94.trailing-spaces
      shopify.ruby-lsp
      simonsiefke.svg-preview
      skellock.just
      slevesque.vscode-3dviewer
      sorbet.sorbet-vscode-extension
      styled-components.vscode-styled-components
      sumneko.lua
      svelte.svelte-vscode
      sweetpad.sweetpad
      swiftlang.swift-vscode
      tailscale.vscode-tailscale
      tamasfe.even-better-toml
      teabyii.ayu
      timonwong.shellcheck
      tobiah.language-pde
      tonybaloney.vscode-pets
      twxs.cmake
      usernamehw.errorlens
      vadimcn.vscode-lldb
      virgilsisoe.hammerspoon
      virgilsisoe.hammerspoon-snippets
      vscjava.migrate-java-to-azure
      vscjava.vscode-gradle
      vscjava.vscode-java-debug
      vscjava.vscode-java-dependency
      vscjava.vscode-java-pack
      vscjava.vscode-java-test
      vscjava.vscode-maven
      vscode-icons-team.vscode-icons
      xshrim.txt-syntax
      yummygum.city-lights-theme
      yusifaliyevpro.vscicons
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
