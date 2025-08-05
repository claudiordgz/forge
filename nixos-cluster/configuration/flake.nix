{
  description = "NixOS Cluster";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-generators.url = "github:nix-community/nixos-generators";
    flake-utils.url = "github:numtide/flake-utils";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { self, nixpkgs, flake-utils, sops-nix, ... }:

  flake-utils.lib.eachDefaultSystem (
    system:
    let
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [ git gnupg sops ];
      };
    }
  ) // {
    nixosConfigurations = let
      mkHost = hostName: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./common/common.nix
          ./common/users.nix
          ./hosts/${hostName}/configuration.nix
          sops-nix.nixosModules.sops
        ];
      };
    in {
      vega = mkHost "vega";
      arcturus = mkHost "arcturus";
      rigel = mkHost "rigel";
    };
  };
}