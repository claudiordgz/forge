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
  
  # Create extra flags list based on role
  extraFlagsList = 
    if isControlPlane then [
      # Server (control plane) flags
      "--disable=traefik"
      "--disable=servicelb"
      "--disable=local-storage"
      "--disable-cloud-controller"
      "--disable-network-policy"
      # add to the isControlPlane branch
      "--flannel-backend=vxlan"
      "--cluster-cidr=10.42.0.0/16"
      "--service-cidr=10.43.0.0/16"
      # GPU labels
      "--node-label=accelerator=nvidia"
      "--node-label=gpu.model=${gpuModel}"
    ] else [
      # Agent (worker) flags
      "--node-label=accelerator=nvidia"
      "--node-label=gpu.model=${gpuModel}"
    ];
  
  # Convert list to space-separated string
  extraFlagsString = lib.concatStringsSep " " extraFlagsList;
in {
  # Enable k3s service
  services.k3s = {
    enable = true;
    role = if isControlPlane then "server" else "agent";
    
    # Server (control plane) configuration - only set for agent nodes
    serverAddr = lib.mkIf (!isControlPlane) "https://10.10.10.5:6443";
    tokenFile = lib.mkIf (!isControlPlane) "/var/lib/rancher/k3s/server/node-token";
    
    # Extra flags as a single string
    extraFlags = extraFlagsString;
  };

  # Configure containerd for k3s (k3s needs containerd, not podman)
  virtualisation.containerd.enable = true;
  boot.kernelModules = [ "br_netfilter" ];
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.ipv4.conf.all.rp_filter" = 0;
  };

  # Networking configuration for k3s
  networking = {
    firewall = {
      trustedInterfaces = [ "cni0" "flannel.1" "kube-ipvs0" ];
      # Allow SSH from anywhere (needed for remote management)
      allowedTCPPorts = [ 22 80 443 ];
      allowedUDPPorts = [ 8472 ]; # flannel VXLAN
      
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
        # Allow nginx-ingress health check port
        iptables -A nixos-fw -p tcp --dport 10254 -j nixos-fw-accept
        
        # Allow Longhorn internal communication ports
        iptables -A nixos-fw -p tcp --dport 9500 -j nixos-fw-accept
        iptables -A nixos-fw -p tcp --dport 9502 -j nixos-fw-accept
        iptables -A nixos-fw -p tcp --dport 9503 -j nixos-fw-accept
        
        # With MetalLB, no need to open ephemeral NodePorts broadly
      '';
    };
  };
} 