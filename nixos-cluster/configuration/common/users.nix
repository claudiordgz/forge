{ config, pkgs, lib, inputs, ... }:

let
  host = config.networking.hostName;
  pubAdmin = "${inputs.keys}/${host}-adminuser.pub";

  cluster = [ "vega" "rigel" "arcturus" ];
  others = builtins.filter (n: n != host) cluster;

  intracomPubsFromOthers =
    map (n: builtins.readFile "${inputs.keys}/${n}-intracom.pub") others;

  adminPubList =
    if builtins.pathExists pubAdmin
    then [ (builtins.readFile pubAdmin) ]
    else [];
in
{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      AllowUsers = [ "admin" "intracom" "root" ];
      StrictModes = true;
    };
    extraConfig = ''
      Match User intracom Address 10.10.10.0/24
        AllowAgentForwarding no
        AllowTcpForwarding no
        X11Forwarding no
        PermitTTY yes
    '';
  };

  users.users = {
    admin = {
      isNormalUser = true;
      extraGroups = [ "wheel" "networkmanager" "podman" ];
      openssh.authorizedKeys.keys = adminPubList;
    };

    root.openssh.authorizedKeys.keys = adminPubList;
  };

  users.users.intracom = {
    isSystemUser = true;
    createHome   = true;
    home         = "/var/lib/intracom";
    group        = "intracom";
    shell        = pkgs.bash;
    # Authorize *other nodes'* intracom keys ONLY here
    openssh.authorizedKeys.keys = intracomPubsFromOthers;
  };
  users.groups.intracom = {};

  # Pin known_hosts so SSH never prompts
  environment.etc."ssh/ssh_known_hosts".source = lib.mkForce "${inputs.keys}/ssh_known_hosts";
  programs.ssh.knownHosts = lib.mkForce {};

  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.firewall.extraCommands = ''
    ip46tables -A INPUT -p tcp --dport 22 ! -s 10.10.10.0/24 -j DROP
  '';

  # Let intracom read system journal and run rootless Podman
  users.users.intracom.extraGroups = [ "systemd-journal" "podman" ];

  # Optional: per-user services for intracom
  systemd.user.services."intracom-agent" = {
    description = "Intracom user agent";
    serviceConfig = { ExecStart = "/var/lib/intracom/agent.sh"; };
    wantedBy = [ "default.target" ];
  };

  assertions = [
    { assertion = builtins.pathExists pubAdmin;
      message   = "Missing admin pubkey at: ${pubAdmin}";
    }
    { assertion = builtins.all (n: builtins.pathExists "${inputs.keys}/${n}-intracom.pub") others;
      message   = "Missing intracom pubkeys for peers ${toString others} under ${inputs.keys}.";
    }
    { assertion = builtins.pathExists "${inputs.keys}/ssh_known_hosts";
      message   = "Missing ${inputs.keys}/ssh_known_hosts (generate with ssh-keyscan).";
    }
  ];
}