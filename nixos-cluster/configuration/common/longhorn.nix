{ config, pkgs, lib, pkgsUnstable, ... }:

let
  inherit (lib) mkOption types mkIf concatMapStringsSep mapAttrsToList listToAttrs;
  defaultMountOptions = [ "nofail" "x-systemd.automount" "x-systemd.device-timeout=1s" ];
  dataMounts = config.locallier.dataMounts;
in {
  options.locallier.dataMounts = mkOption {
    type = with types; listOf (submodule ({ ... }: {
      options = {
        label = mkOption {
          type = types.str;
          description = "Filesystem label to mount, e.g. LONGHORN1";
        };
        mountPoint = mkOption {
          type = types.str;
          description = "Target directory where the device will be mounted";
        };
        fsType = mkOption {
          type = types.str;
          default = "ext4";
          description = "Filesystem type";
        };
        mountOptions = mkOption {
          type = types.listOf types.str;
          default = defaultMountOptions;
          description = "Mount options";
        };
      };
    }));
    default = [
      { label = "LONGHORN1"; mountPoint = "/mnt/longhorn1"; }
    ];
    description = "Cluster-wide data mounts declared by disk label";
  };

  config = {
    services.openiscsi = {
      enable = true;
      # Use a stable IQN; you can change the prefix to your org/domain.
      # This interpolates each host’s name automatically.
      name = "iqn.2025-08.locallier:${config.networking.hostName}";
    };

    # Make /usr/bin/iscsiadm available for Longhorn and ensure mount dirs exist
    systemd.tmpfiles.rules =
      [
        "L /usr/bin/iscsiadm - - - - /run/current-system/sw/bin/iscsiadm"
        "L /usr/sbin/iscsiadm - - - - /run/current-system/sw/bin/iscsiadm"
      ]
      ++ (map (m: "d ${m.mountPoint} 0755 root root -") dataMounts);

    # Generate fileSystems entries for each declared data mount
    fileSystems = listToAttrs (map (m: {
      name = m.mountPoint;
      value = {
        device = "/dev/disk/by-label/${m.label}";
        fsType = m.fsType;
        options = m.mountOptions;
      };
    }) dataMounts);
  };
}
