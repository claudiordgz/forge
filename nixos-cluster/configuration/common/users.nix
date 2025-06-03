{ config, lib, pkgs, ... }:

let
  host = config.networking.hostName;
in
{
  sops.secrets."sshKeys/${host}/adminuser" = {
    neededForUsers = true;
    path = "/etc/ssh/keys/vega-adminuser";
    mode = "0444";
  };

  users.mutableUsers = false;

  users.users.root.openssh.authorizedKeys.keyFiles = [
    config.sops.secrets."sshKeys/${host}/adminuser".path
  ];
}