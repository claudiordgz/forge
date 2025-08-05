{
  description = "NixOS Cluster";

  inputs = {
    nixpkgs.url          = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-generators.url = "github:nix-community/nixos-generators";
    flake-utils.url      = "github:numtide/flake-utils";

    keys = {
      url   = "path:./keys";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, keys, ... }@inputs:

  flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.default = pkgs.mkShell { packages = with pkgs; [ git gnupg ]; };
    }
  ) // {

    nixosConfigurations =
      let
        mkHost = hostName: nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          specialArgs = { inherit inputs keys pkgsUnstable; };

          modules = [
            ./common/common.nix
            ./common/users.nix
            (./hosts + "/${hostName}/configuration.nix")
          ];
        };
      in {
        vega     = mkHost "vega";
        arcturus = mkHost "arcturus";
        rigel    = mkHost "rigel";
      };
  };
}