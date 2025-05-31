{ config, pkgs, ... }:

let
  host = config.networking.hostName;
in {
  networking.domain = "locallier.com";

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.PermitRootLogin = "no";

  sops.secrets.adminKey = {
    key = "sshKeys.${host}.adminuser";
    sopsFile = ../secrets.yaml;
  };

  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "podman" ];
    openssh.authorizedKeys.keyFiles = [ config.sops.secrets.adminKey.path ];
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  environment.systemPackages = with pkgs; [
    podman
    podman-compose
    opentofu
    kubectl
    ethtool iperf3 speedtest-cli
    parted lvm2 btrfs-progs nvme-cli
    glxinfo mesa-demos pciutils
    htop curl git vim tmux jq
  ];
  
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [
    "1password-cli"
  ];

  hardware.nvidia-container-toolkit.enable = true;

  system.stateVersion = "24.05";
}
