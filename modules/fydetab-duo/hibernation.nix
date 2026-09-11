{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo.hibernation;
  rootDevice = config.fileSystems."/".device;
in
{
  options.hardware.fydetabduo.hibernation = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Set up hibernation (suspend-to-disk) on the btrfs root: creates a
        swapfile if missing, registers it as a swap device, and adds the
        `resume=`/`resume_offset=` kernel parameters.

        FydeOS has no S4, so this is opt-in. Set `resumeOffset` to the
        value from `btrfs inspect-internal map-swapfile <swapfile>`.
      '';
    };

    swapSize = lib.mkOption {
      type = lib.types.str;
      default = "12G";
      description = ''
        Size passed to `btrfs filesystem mkswapfile`. Must be larger than
        the device's RAM (FydeTab Duo: 7.7 GiB) to hold a full RAM image.
      '';
    };

    swapFile = lib.mkOption {
      type = lib.types.str;
      default = "/swap/swapfile";
      description = ''
        Path of the btrfs swapfile. The parent directory must exist
        (e.g., a top-level `@swap` subvolume mounted at `/swap`).
      '';
    };

    resumeDevice = lib.mkOption {
      type = lib.types.str;
      default = rootDevice;
      description = ''
        Block device holding the swapfile, for the `resume=` kernel
        parameter. Defaults to the root device (the swapfile lives on the
        root filesystem).
      '';
    };

    resumeOffset = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = ''
        Physical offset of the swapfile's first block, in 4096-byte units
        - the `resume_offset=` kernel parameter. This depends on where the
        file was physically allocated, so it must be obtained after the swapfile exists:

          sudo btrfs filesystem mkswapfile -s 12G /swap/swapfile
          sudo btrfs inspect-internal map-swapfile /swap/swapfile
          # -> "Resume offset: NNNNN" -> resumeOffset = NNNNN

        If the swapfile is recreated the offset may change, so do update it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.resumeOffset != null;
        message = "hardware.fydetabduo.hibernation.resumeOffset must be set (see `btrfs inspect-internal map-swapfile`).";
      }
    ];

    # Create the swapfile on the root filesystem if it is missing.
    # Ordered using RequiresMountsFor so systemd starts it only after /swap is
    # mounted, making sure the swap.target graph is clean (no local-fs <-> swap).
    systemd.services.create-swapfile = {
      description = "Create btrfs swapfile if absent";
      wantedBy = [ "swap.target" ];
      unitConfig.RequiresMountsFor = [ (dirOf cfg.swapFile) ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.btrfs-progs ];
      script = ''
        if [ ! -e ${cfg.swapFile} ]; then
          btrfs filesystem mkswapfile -s ${cfg.swapSize} ${cfg.swapFile}
        fi
      '';
    };

    swapDevices = [ { device = cfg.swapFile; } ];

    boot.kernelParams = [
      "resume=${cfg.resumeDevice}"
      "resume_offset=${toString cfg.resumeOffset}"
    ];
  };
}
