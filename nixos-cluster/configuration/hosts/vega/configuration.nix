{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "vega";
  
  # Control plane specific configuration
  services.k3s.extraServerArgs = [
    "--node-label=node.kubernetes.io/role=control-plane"
    "--node-label=accelerator=nvidia"
    "--node-label=gpu.model=rtx3060"
  ];
}

