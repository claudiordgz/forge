{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "vega";

  sops = {
    defaultSopsFile = "../../../secrets.yaml";
    age = {
      keyFile = "/root/.config/sops/age/keys.txt";
      generateKey = false;
    };
    secrets."sshKeys.vega.adminuser" = {
      path = "/etc/ssh/keys/vega-adminuser";
    };
  };
}

