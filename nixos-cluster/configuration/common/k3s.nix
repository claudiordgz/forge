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
  services.k3s = {
    enable = true;
    role = if isControlPlane then "server" else "agent";
    
    # Server (control plane) configuration
    serverAddr = if isControlPlane then null else "https://10.10.10.5:6443";
    tokenFile = if isControlPlane then null else "/var/lib/rancher/k3s/server/node-token";
    
    # Extra args for all nodes
    extraFlags = [
      "--node-label=accelerator=nvidia"
      "--node-label=gpu.model=${gpuModel}"
    ] ++ (if isControlPlane then [
      "--disable=traefik"  # We'll use nginx-ingress instead
      "--disable=servicelb"  # We'll use metallb instead
      "--disable=local-storage"
      "--disable-cloud-controller"
      "--disable-network-policy"
      "--flannel-backend=none"  # We'll use calico
      "--cluster-cidr=10.244.0.0/16"
      "--service-cidr=10.96.0.0/12"
      "--node-label=node.kubernetes.io/role=control-plane"
    ] else [
      "--node-label=node.kubernetes.io/role=worker"
    ]);
  };

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

  # Add GPU node labels and taints
  systemd.services.k3s-agent = lib.mkIf (!isControlPlane) {
    preStart = ''
      # Add GPU labels after k3s starts
      sleep 10
      kubectl label node $(hostname) accelerator=nvidia --overwrite || true
    '';
  };
} 