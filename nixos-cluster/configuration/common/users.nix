{ config, lib, pkgs, ... }:

let
  host = config.networking.hostName;
  secretPath = "sshKeys/${host}/adminuser";
in
{
  sops.secrets.${secretPath} = {
    neededForUsers = true;
    path = "/home/admin/.ssh/adminuser.pub";
    owner = config.users.users.admin.name;
    inherit (config.users.users.admin) group;
  };

  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
  services.sshd.enable = true;  
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "podman" ];
    openssh.authorizedKeys.keys = [
      (builtins.readFile ./keys/adminuser.pub)
    ];
  };
}