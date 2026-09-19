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
    #
    # This runs at activation time (after local-fs.target, before sysinit.target)
    # rather than as a systemd service wanted by swap.target: the generated .swap
    # unit for a swapfile on the root fs orders swap.target after local-fs.target,
    # so a service that both wanted swap.target and needed the root fs mounted
    # would cause an ordering cycle (swap <-> local-fs/sysinit). Activation scripts
    # defintely run before swap.target activates the .swap unit, so the swapfile
    # already exists and no cycle can occur :).
    system.activationScripts.createSwapfile = lib.mkAfter ''
      mkdir -p "$(dirname ${cfg.swapFile})"
      if [ ! -e ${cfg.swapFile} ]; then
        ${pkgs.btrfs-progs}/bin/btrfs filesystem mkswapfile -s ${cfg.swapSize} ${cfg.swapFile}
      fi
    '';

    swapDevices = [ { device = cfg.swapFile; } ];

    # Temporarily disable ZRAM before hibernation to prevent conflicts
    # between the swap file and ZRAM.
    systemd.services.zram-hibernate-pre = {
      description = "Swap off ZRAM before hibernate";
      before = [
        "systemd-hibernate.service"
        "systemd-hybrid-sleep.service"
        "systemd-suspend-then-hibernate.service"
      ];
      wantedBy = [
        "systemd-hibernate.service"
        "systemd-hybrid-sleep.service"
        "systemd-suspend-then-hibernate.service"
      ];
      unitConfig.ConditionPathExists = "/dev/zram0";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "zram-pre-hibernate" ''
          if grep -q "/dev/zram0" /proc/swaps; then
            ${pkgs.util-linux}/bin/swapoff /dev/zram0 2>/dev/null || true
          fi
        '';
      };
    };

    systemd.services.zram-hibernate-post = {
      description = "Re-enable ZRAM swap with priority 5 after resume";
      after = [
        "systemd-hibernate.service"
        "systemd-hybrid-sleep.service"
        "systemd-suspend-then-hibernate.service"
      ];
      wantedBy = [
        "systemd-hibernate.service"
        "systemd-hybrid-sleep.service"
        "systemd-suspend-then-hibernate.service"
      ];
      unitConfig.ConditionPathExists = "/dev/zram0";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "zram-post-hibernate" ''
          if ! grep -q "/dev/zram0" /proc/swaps; then
            ${pkgs.util-linux}/bin/swapon -p 5 /dev/zram0 2>/dev/null || true
          fi
        '';
      };
    };

    boot.kernelParams = [
      "resume=${cfg.resumeDevice}"
      "resume_offset=${toString cfg.resumeOffset}"
    ];
  };
}
