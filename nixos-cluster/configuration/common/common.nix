{ config, pkgs, pkgsUnstable, ... }:

let
  host = config.networking.hostName;
in {
  networking.domain = "locallier.com";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;

  nixpkgs.config.allowUnfree = true;

  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;  # <-- required
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
    autoUpdate = true;
  };

  environment.systemPackages = with pkgs; [
    podman
    podman-compose
    opentofu
    age
    kubectl
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

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.production;
    modesetting.enable = true;
    powerManagement.enable = false;
    open = false;
    nvidiaSettings = true;
  };

  hardware.nvidia-container-toolkit.enable = true;

  systemd.services.nvidia-persistence-mode = {
    description = "Enable NVIDIA persistence mode";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/nvidia-smi -pm 1";
    };
  };

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
