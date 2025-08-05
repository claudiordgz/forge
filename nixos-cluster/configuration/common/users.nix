{ config, pkgs, lib, inputs, keys, ... }:

let
  host = config.networking.hostName;
in
{
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
  services.sshd.enable = true;  
  users.users = {
    admin = {
      isNormalUser = true;
      extraGroups = [ "wheel" "networkmanager" "podman" ];
      openssh.authorizedKeys.keyFiles = [
        (keys + "/${host}-adminuser.pub")
      ];
    };
    root.openssh.authorizedKeys.keyFiles = [
      (inputs.keys + "/${host}-adminuser.pub")
    ];
  };
}