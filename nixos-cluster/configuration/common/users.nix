{ config, pkgs, lib, inputs, keys, ... }:

let
  host = config.networking.hostName;
  pub  = "${keys}/${host}-adminuser.pub";
in
{
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
  services.sshd.enable = true;  
  users.users = {
    admin = {
      isNormalUser = true;
      extraGroups = [ "wheel" "networkmanager" "podman" ];
      openssh.authorizedKeys.keys = [
        (builtins.readFile pub)
      ];
    };
    root.openssh.authorizedKeys.keys = [
      (builtins.readFile pub)
    ];
  };
}