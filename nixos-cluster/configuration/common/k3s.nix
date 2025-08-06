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

  # Path to the dashboard manifest file
  dashboardManifestFile = ../../kubernetes/dashboard.yaml;

  # Path to cert-manager manifest file
  certManagerManifestFile = ../../kubernetes/cert-manager.yaml;

  # Path to Let's Encrypt issuer manifest file
  letsencryptIssuerManifestFile = ../../kubernetes/letsencrypt-issuer.yaml;
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

  # Deploy Kubernetes Dashboard automatically when k3s starts
  systemd.services.k3s-dashboard = lib.mkIf isControlPlane {
    description = "Deploy Kubernetes Dashboard";
    wantedBy = [ "k3s.service" ];
    after = [ "k3s.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply -f ${dashboardManifestFile}";
      ExecStop = "${pkgs.kubectl}/bin/kubectl delete -f ${dashboardManifestFile} --ignore-not-found=true";
    };
  };

  # Deploy cert-manager automatically when k3s starts
  systemd.services.k3s-cert-manager = lib.mkIf isControlPlane {
    description = "Deploy cert-manager";
    wantedBy = [ "k3s.service" ];
    after = [ "k3s.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply -f ${certManagerManifestFile}";
      ExecStop = "${pkgs.kubectl}/bin/kubectl delete -f ${certManagerManifestFile} --ignore-not-found=true";
    };
  };

  # Deploy Let's Encrypt issuer after cert-manager
  systemd.services.k3s-letsencrypt-issuer = lib.mkIf isControlPlane {
    description = "Deploy Let's Encrypt ClusterIssuer";
    wantedBy = [ "k3s-cert-manager.service" ];
    after = [ "k3s-cert-manager.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply -f ${letsencryptIssuerManifestFile}";
      ExecStop = "${pkgs.kubectl}/bin/kubectl delete -f ${letsencryptIssuerManifestFile} --ignore-not-found=true";
    };
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
        # Allow Kubernetes Dashboard access
        iptables -A nixos-fw -p tcp --dport 30443 -s 10.10.10.0/24 -j nixos-fw-accept
      '';
    };
  };
} 