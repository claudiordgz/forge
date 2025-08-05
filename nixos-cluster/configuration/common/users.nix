{ config, pkgs, lib, inputs, keys, ... }:

let
  host = config.networking.hostName;
  pub  = "${keys}/${host}-adminuser.pub";
in
{
  services.openssh.enable = true;

  # Make absolutely sure no one else sets keyFiles
  users.users.admin.openssh.authorizedKeys.keyFiles = lib.mkForce [ ];
  users.users.root.openssh.authorizedKeys.keyFiles  = lib.mkForce [ ];

  users.users = {
    admin = {
      isNormalUser = true;
      extraGroups  = [ "wheel" "networkmanager" "podman" ];
      openssh.authorizedKeys.keys = [ (builtins.readFile pub) ];
    };
    root.openssh.authorizedKeys.keys = [ (builtins.readFile pub) ];
  };

  # Also ensure no stray /etc entries get created elsewhere:
  environment.etc."ssh/authorized_keys.d/admin".enable = lib.mkForce false;
  environment.etc."ssh/authorized_keys.d/root".enable  = lib.mkForce false;
}