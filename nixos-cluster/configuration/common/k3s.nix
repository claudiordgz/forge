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
    
    # Server (control plane) configuration - only set for agent nodes
    serverAddr = lib.mkIf (!isControlPlane) "https://10.10.10.5:6443";
    tokenFile = lib.mkIf (!isControlPlane) "/var/lib/rancher/k3s/server/node-token";
  };

  # Configure containerd for k3s (k3s needs containerd, not podman)
  virtualisation.containerd.enable = true;
} 