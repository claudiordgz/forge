{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];
  
  networking.hostName = "vega";
}

