{ config, pkgs, lib, inputs, ... }:

let
  host = config.networking.hostName;
  pub  = "${inputs.keys}/${host}-adminuser.pub"; 
in
{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

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
    message   = "Missing pubkey at: ${pub}";
  }];
}