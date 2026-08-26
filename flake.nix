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
    # Daily bank -> Notion sync (provides a nix-darwin module).
    notion-finance-sync = {
      url = "github:alexjmiller5/notion-finance-sync";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Weekly Screen Time + call history snapshots (each provides a nix-darwin module).
    screentime-backup.url = "github:alexjmiller5/screentime-backup";
    callhistory-backup.url = "github:alexjmiller5/callhistory-backup";
    # age-encrypted secrets, decrypted at activation via the host SSH key.
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
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
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, nix-homebrew, notion-finance-sync, screentime-backup, callhistory-backup, agenix, cherri, nix-vscode-extensions, workspace-snapshot, nix-openclaw-tools }:
    let
      username = "alexmiller";
      mkHost = { host, home }: nix-darwin.lib.darwinSystem {
        specialArgs = { inherit username; };
        modules = [
          host
          ./modules/macos-defaults.nix
          agenix.darwinModules.default
          notion-finance-sync.darwinModules.default
          screentime-backup.darwinModules.default
          callhistory-backup.darwinModules.default
          nix-homebrew.darwinModules.nix-homebrew
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
            home-manager.sharedModules = [ workspace-snapshot.homeModules.default ];
            home-manager.extraSpecialArgs = { inherit username cherri nix-vscode-extensions nix-openclaw-tools; };
            home-manager.users.${username} = import home;
          }
        ];
      };
    in
    {
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
        op-claude-sa = ./home/op-claude-sa.nix;
        ai-agent = ./home/ai-agent.nix;
        cli-tools = ./home/cli-tools.nix;
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
      };
    };
}
