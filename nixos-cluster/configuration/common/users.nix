{ config, lib, pkgs, ... }:

let
  host = config.networking.hostName;
  secretPath = "sshKeys/${host}/adminuser";
in
{
  sops.secrets.${secretPath} = {
    neededForUsers = true;
  };

  users.mutableUsers = false;
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
  services.sshd.enable = true;  
  users.users.root.openssh.authorizedKeys.keys = [
    config.sops.secrets.${secretPath}.path
  ];
}