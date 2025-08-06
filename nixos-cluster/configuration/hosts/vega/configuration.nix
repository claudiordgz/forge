{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./k3s.nix
  ];

  networking.hostName = "vega";
}

