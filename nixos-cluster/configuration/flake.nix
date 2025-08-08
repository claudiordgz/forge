{
  description = "NixOS Cluster";

  ############################################################################
  # 🔗 Inputs
  ############################################################################
  inputs = {
    nixpkgs.url          = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-generators.url = "github:nix-community/nixos-generators";
    flake-utils.url      = "github:numtide/flake-utils";

    # path-based input that pulls ./keys (git-ignored)
    keys = {
      url   = "path:/var/lib/nixos-cluster/keys";
      flake = false;
    };
  };

  ############################################################################
  # 📦 Outputs
  ############################################################################
  outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils, ... }@inputs:
  let
    # Helper to import the stable channel for any system
    pkgsFor = system: import nixpkgs { inherit system; };
  in

  # ───── Dev shells for every supported system ──────────────────────────────
  flake-utils.lib.eachDefaultSystem (system:
    {
      devShells.default = (pkgsFor system).mkShell {
        packages = with (pkgsFor system); [ git gnupg ];
      };
    }
  ) //

  # ───── NixOS host definitions ─────────────────────────────────────────────
  {
    nixosConfigurations =
      let
        # One shared import of the unstable channel (x86_64 only here)
        pkgsUnstable = import nixpkgs-unstable {
          system = "x86_64-linux";
          config = { allowUnfree = true; };
        };

        mkHost = hostName:
          nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";

            # Pass everything a module might need
            specialArgs = {
              inherit inputs pkgsUnstable;
            };

            modules = [
              ./common/common.nix
              ./common/users.nix
              ./common/k3s.nix
              ./common/longhorn.nix
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