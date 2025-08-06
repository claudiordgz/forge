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

  # Networking configuration for k3s
  networking = {
    firewall = {
      # Allow SSH from anywhere (needed for remote management)
      allowedTCPPorts = [ 22 ];
      
      # Allow k3s ports only from local network
      extraCommands = ''
        # Allow k3s API server (6443) only from local network
        ${lib.optionalString isControlPlane ''
          iptables -A nixos-fw -p tcp --dport 6443 -s 10.10.10.0/24 -j nixos-fw-accept
          ip6tables -A nixos-fw -p tcp --dport 6443 -j nixos-fw-accept
        ''}
        
        # Allow k3s metrics (10250) only from local network
        iptables -A nixos-fw -p tcp --dport 10250 -s 10.10.10.0/24 -j nixos-fw-accept
        ip6tables -A nixos-fw -p tcp --dport 10250 -j nixos-fw-accept
        
        # Allow k3s node communication (UDP) only from local network
        iptables -A nixos-fw -p udp --dport 8472 -s 10.10.10.0/24 -j nixos-fw-accept
        iptables -A nixos-fw -p udp --dport 51820 -s 10.10.10.0/24 -j nixos-fw-accept
        ip6tables -A nixos-fw -p udp --dport 8472 -j nixos-fw-accept
        ip6tables -A nixos-fw -p udp --dport 51820 -j nixos-fw-accept
      '';
    };
  };
} 