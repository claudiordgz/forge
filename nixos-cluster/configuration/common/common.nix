{ config, pkgs, lib, pkgsUnstable, ... }:

let
  host = config.networking.hostName;
in {
  networking.domain = "locallier.com";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;

  nixpkgs.config.allowUnfree = true;
  environment.variables = {
    K3S_KUBECONFIG_MODE = "644";
  };

  # GL userspace (old-style names; fine on 24.05/24.11)
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true; # required for NVIDIA userland (32-bit GL)
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork = {
      settings = {
        dns_enabled = true;
      };
    };
    autoPrune.enable = true;
  };

  environment.systemPackages = with pkgs; [
    podman
    podman-compose
    opentofu
    age
    openiscsi
    k3s helm kubectl kubernetes-helm
    ethtool iperf3 speedtest-cli
    parted lvm2 btrfs-progs nvme-cli
    glxinfo mesa-demos pciutils
    htop curl git vim tmux jq
    pkgsUnstable._1password-cli yq
    ookla-speedtest
    cudatoolkit
    cudaPackages.cudnn
    cudaPackages.nccl
  ];

  # Load NVIDIA kernel module even on headless nodes
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.production;
    modesetting.enable = true;
    powerManagement.enable = false;
    open = false;
    nvidiaSettings = true;
    nvidiaPersistenced = true; 
  };

  # NVIDIA container runtime hooks (CDI works with Podman)
  hardware.nvidia-container-toolkit.enable = true;

  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  system.stateVersion = "24.11";
}
