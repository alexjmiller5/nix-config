{
  description = "Alex's nix-darwin machine configs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Installs and pins Homebrew itself declaratively (no curl|bash installer).
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    # Weekly Screen Time + call history snapshots (each provides a nix-darwin module).
    screentime-backup.url = "github:alexjmiller5/screentime-backup";
    callhistory-backup.url = "github:alexjmiller5/callhistory-backup";
    # age-encrypted secrets, decrypted at activation via the host SSH key.
    # darwin + home-manager follows: without them agenix pins its own copies
    # (they showed up in flake.lock as darwin / home-manager_2).
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.darwin.follows = "nix-darwin";
      inputs.home-manager.follows = "home-manager";
    };
    # Cherri language compiler (iOS Shortcuts) — not in nixpkgs; upstream ships a flake.
    cherri = {
      url = "github:electrikmilk/cherri";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Nightly-updated VS Code marketplace mirror — extension set declared in
    # home/vscode.nix; versions ride the weekly input bump.
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Workspace Snapshot — ships a home-manager module (Spoon + scripts +
    # VS Code extension); enabled in home/macbook-air.nix.
    workspace-snapshot = {
      url = "github:alexjmiller5/workspace-snapshot";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # openclaw tool packages (gogcli et al.) at upstream release cadence —
    # nixpkgs lags gogcli by months at its weekly release pace.
    nix-openclaw-tools = {
      url = "github:openclaw/nix-openclaw-tools";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # life-data — schema-agnostic personal data store (`life` CLI); installed
    # on both machines, enabled in home/common.nix.
    life-data = {
      url = "github:alexjmiller5/life-data";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Claude Code plugins, pinned and loaded in place (see home/claude-plugins.nix).
    # `claude plugin install` is an imperative install that leaves a fresh
    # machine with nothing, so the sources are inputs and ride the weekly bump.
    # Not flakes: these are plugin repos, consumed as plain source trees.
    claude-plugins-official = {
      url = "github:anthropics/claude-plugins-official";
      flake = false;
    };
    claude-plugin-superpowers = {
      url = "github:obra/superpowers";
      flake = false;
    };
    claude-plugin-ponytail = {
      url = "github:DietrichGebert/ponytail";
      flake = false;
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      nix-darwin,
      home-manager,
      ...
    }:
    let
      username = "alexmiller";
      mkHost =
        { host, home }:
        nix-darwin.lib.darwinSystem {
          specialArgs = { inherit username; };
          modules = [
            host
            ./modules/darwin-base.nix
            ./modules/macos-defaults.nix
            inputs.agenix.darwinModules.default
            inputs.screentime-backup.darwinModules.default
            inputs.callhistory-backup.darwinModules.default
            inputs.nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                enable = true;
                user = username;
              };
            }
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.sharedModules = [ inputs.workspace-snapshot.homeModules.default ];
              # Explicit per-input args (not `inherit inputs`) on purpose: each
              # exported homeModule documents exactly what a consumer must pass.
              home-manager.extraSpecialArgs = {
                inherit username;
                inherit (inputs)
                  cherri
                  nix-vscode-extensions
                  nix-openclaw-tools
                  life-data
                  claude-plugins-official
                  claude-plugin-superpowers
                  claude-plugin-ponytail
                  ;
              };
              home-manager.users.${username} = import home;
            }
          ];
        };
    in
    {
      # RFC 166 formatting: `nix fmt` (also `just fmt`).
      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt;

      darwinConfigurations."mac-mini" = mkHost {
        host = ./hosts/mac-mini.nix;
        home = ./home/mac-mini.nix;
      };
      darwinConfigurations."macbook-air" = mkHost {
        host = ./hosts/macbook-air.nix;
        home = ./home/macbook-air.nix;
      };

      # Reusable home-manager modules, for consumption by other flakes
      # (e.g. a work-laptop config pinning this repo as an input).
      # git.nix identity uses mkDefault, so consumers can override the email.
      homeModules = {
        git = ./home/git.nix;
        zsh = ./home/zsh.nix;
        scripts = ./home/scripts.nix;
        op-agent-sa = ./home/op-agent-sa.nix;
        ai-agent = ./home/ai-agent.nix;
        cli-tools = ./home/cli-tools.nix;
        agent-config-links = ./home/agent-config-links.nix;
        # claude-plugins needs the consumer to pass claude-plugins-official,
        # claude-plugin-superpowers and claude-plugin-ponytail via extraSpecialArgs
        claude-plugins = ./home/claude-plugins.nix;
        machine-vault-git = ./home/machine-vault-git.nix;
        # op-wrappers needs the consumer to pass nix-openclaw-tools via extraSpecialArgs
        op-wrappers = ./home/op-wrappers.nix;
        # life-data needs the consumer to pass life-data via extraSpecialArgs
        life-data = ./home/life-data.nix;
        # dev-tools needs the consumer to pass cherri via extraSpecialArgs
        dev-tools = ./home/dev-tools.nix;
        ghostty = ./home/ghostty.nix;
        # vscode needs the consumer to pass nix-vscode-extensions via extraSpecialArgs
        vscode = ./home/vscode.nix;
        aliases-dev = ./home/aliases/dev.nix;
        aliases-ai = ./home/aliases/ai.nix;
        aliases-infra = ./home/aliases/infra.nix;
        macos-duti = ./home/macos/duti.nix;
        macos-menu-bar = ./home/macos/menu-bar.nix;
        macos-spotlight-raycast = ./home/macos/spotlight-raycast.nix;
        macos-nightlight = ./home/macos/nightlight.nix;
        macos-chrome-extension-storage = ./home/macos/chrome-extension-storage.nix;
        macos-chrome-remote-debugging = ./home/macos/chrome-remote-debugging.nix;
        macos-notification-prefs = ./home/macos/notification-prefs.nix;
      };
    };
}
