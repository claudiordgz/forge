{ config, pkgs, lib, ... }:

let
  # Helper function to check if this is the control plane node
  isControlPlane = config.networking.hostName == "vega";
  
  # GPU model mapping based on hostname
  gpuModel = {
    "vega" = "rtx3060";
    "rigel" = "rtx3080";
    "arcturus" = "rtx2080";
  }.${config.networking.hostName} or "unknown";
in {
  # Enable k3s service
  services.k3s.enable = true;

  # Environment variables for k3s
  environment.variables = {
    K3S_KUBECONFIG_MODE = "644";
  };

  # Add k3s to system packages
  environment.systemPackages = with pkgs; [
    k3s
    kubectl
    helm
    kubernetes-helm
  ];

  # Networking configuration for k3s
  networking = {
    firewall = {
      # Allow k3s API server (control plane only)
      allowedTCPPorts = lib.mkIf isControlPlane [ 6443 ] ++ [ 10250 ];
      # Allow k3s node communication
      allowedUDPPorts = [ 8472 51820 ];
    };
  };

  # Persist k3s data
  systemd.services.k3s = {
    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # Add GPU support
  hardware.nvidia-container-toolkit.enable = true;
  
  # Configure containerd for GPU support
  virtualisation.containerd = {
    enable = true;
    settings = {
      plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia = {
        privileged_without_host_devices = false;
        runtime_engine = "";
        runtime_root = "";
        runtime_type = "io.containerd.runc.v2";
        options = {
          BinaryName = "/usr/bin/nvidia-container-runtime";
          SystemdCgroup = true;
        };
      };
    };
  };
} 