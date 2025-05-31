{
  description = "NixOS Cluster";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-generators.url = "github:nix-community/nixos-generators";
    flake-utils.url = "github:numtide/flake-utils";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { self, nixpkgs, flake-utils, sops-nix, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ git gnupg sops ];
        };
      }
    ) // {
      nixosConfigurations = {
        vega = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ 
            ./common/common.nix 
            ./hosts/vega/configuration.nix 
            sops-nix.nixosModules.sops
          ];
        };
        arcturus = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ 
            ./common/common.nix 
            ./hosts/arcturus/configuration.nix 
            sops-nix.nixosModules.sops
          ];
        };
        rigel = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ 
            ./common/common.nix 
            ./hosts/rigel/configuration.nix 
            sops-nix.nixosModules.sops
          ];
        };
      };
    };
}