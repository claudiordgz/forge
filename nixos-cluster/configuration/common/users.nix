{ config, lib, pkgs, ... }:

let
  host = config.networking.hostName;
  secretPath = "sshKeys.${host}.adminuser";
in
{
  sops.secrets.${secretPath} = {
    neededForUsers = true;
    path = "/etc/ssh/keys/${host}-adminuser";
    mode = "0444";
  };

  users.mutableUsers = false;

  users.users.root.openssh.authorizedKeys.keyFiles = [
    config.sops.secrets.${secretPath}.path
  ];
}