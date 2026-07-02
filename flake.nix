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
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, nix-homebrew }:
    let
      username = "alexmiller";
    in
    {
      darwinConfigurations."mac-mini" = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit username; };
        modules = [
          ./hosts/mac-mini.nix
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
            home-manager.extraSpecialArgs = { inherit username; };
            home-manager.users.${username} = import ./home.nix;
          }
        ];
      };
    };
}
