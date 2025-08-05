{ config, pkgs, lib, ... }:

let
  host = config.networking.hostName;
  keysPath = builtins.filterSource (_path: _type: true) ./../keys;

  pub = keysPath + "/${host}-adminuser.pub";
in
{
  services.openssh.enable = true;

  # Belt-and-suspenders: ensure nobody else injects keyFiles
  users.users.admin.openssh.authorizedKeys.keyFiles = lib.mkForce [ ];
  users.users.root.openssh.authorizedKeys.keyFiles  = lib.mkForce [ ];

  users.users = {
    admin = {
      isNormalUser  = true;
      extraGroups   = [ "wheel" "networkmanager" "podman" ];
      openssh.authorizedKeys.keys = [ (builtins.readFile pub) ];
    };

    root.openssh.authorizedKeys.keys = [ (builtins.readFile pub) ];
  };

  # Optional: catch missing pub early with a clear message
  assertions = [{
    assertion = builtins.pathExists pub;
    message   = "Missing ${pub}. Did you run ./keys_and_config.sh ${host}?";
  }];
}