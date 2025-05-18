{ config, pkgs, ... }:

{
  imports = [];

  networking.domain = "locallier.com";

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.PermitRootLogin = "no";

  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
    ];
  };

  system.stateVersion = "24.05";
}
