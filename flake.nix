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
    # age-encrypted secrets, decrypted at activation via the host SSH key.
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, nix-homebrew, notion-finance-sync, agenix }:
    let
      username = "alexmiller";
    in
    {
      darwinConfigurations."mac-mini" = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit username; };
        modules = [
          ./hosts/mac-mini.nix
          ./modules/macos-defaults.nix
          agenix.darwinModules.default
          notion-finance-sync.darwinModules.default
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
            home-manager.extraSpecialArgs = { inherit username; };
            home-manager.users.${username} = import ./home.nix;
          }
        ];
      };
    };
}
