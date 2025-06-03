{ config, lib, pkgs, ... }:

let
  host = config.networking.hostName;
  secretPath = "sshKeys/${host}/adminuser";
in
{
  sops.secrets.${secretPath} = {
    neededForUsers = true;
    path = "/root/.ssh/${host}-adminuser.pub";
  };

  users.mutableUsers = false;
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
  services.sshd.enable = true;  
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "podman" ];
    openssh.authorizedKeys.keys = [
    ];
  };
}