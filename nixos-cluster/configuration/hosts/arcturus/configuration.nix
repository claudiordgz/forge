{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "arcturus";
  
  # Worker node specific configuration
  services.k3s.extraAgentArgs = [
    "--node-label=accelerator=nvidia"
    "--node-label=gpu.model=rtx2080"
  ];
}
