{
  description = "NixOS configuration";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
  inputs.nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-24.05-darwin";
  inputs.nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

  inputs.nix-darwin.url = "github:LnL7/nix-darwin";
  inputs.nix-darwin.inputs.nixpkgs.follows = "nixpkgs-darwin";

  inputs.home-manager.url = "github:nix-community/home-manager/release-24.05";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

  outputs = inputs @ { nixpkgs, nixpkgs-darwin, nixpkgs-unstable, nix-darwin, home-manager, ... }:
    let
      linux_system = "x86_64-linux";
      linux_pkgs = nixpkgs.legacyPackages.${linux_system};
      linux_unstable = import nixpkgs-unstable { system = linux_system; };
      darwin_system = "aarch64-darwin";
      darwin_pkgs = nixpkgs.legacyPackages.${darwin_system};
      darwin_unstable = import nixpkgs-unstable { system = darwin_system; };
    in {
      # home-manager switch --flake .#ryankanno@linux
      homeConfigurations."ryankanno@linux" = home-manager.lib.homeManagerConfiguration {
        pkgs = linux_pkgs;
        modules = [ ./linux.nix ];
        extraSpecialArgs = { unstable = linux_unstable; };
      };
      # home-manager switch --flake .#ryankanno@macmini
      homeConfigurations."ryankanno@macmini" = home-manager.lib.homeManagerConfiguration {
        pkgs = darwin_pkgs;
        modules = [ ./darwin.nix ];
        extraSpecialArgs = { unstable = darwin_unstable; };
      };
    };
}
