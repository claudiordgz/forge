{ config, pkgs, ... }:

{
  imports = [];

  networking.domain = "locallier.com";

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.PermitRootLogin = "no";

  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "podman" ];
    openssh.authorizedKeys.keys = [
    ];
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
    htop curl git vim tmux
  ];

  hardware.nvidia-container-toolkit.enable = true;

  system.stateVersion = "24.05";
}
