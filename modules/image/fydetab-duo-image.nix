{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.fydetabImage;
in {
  options.fydetabImage = {
    enable = lib.mkEnableOption "building a FydeTab Duo disk image of this system";

    compress = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Compress the final image with zstd.
      '';
    };

    snapshots = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Mount the btrfs top level at /snapshots so `fydetab-snapshot`
          can create and roll back to system snapshots.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.hardware.fydetabduo.enable or false;
        message = "fydetabImage requires hardware.fydetabduo.enable = true.";
      }
      {
        assertion = config.boot.loader.fydetabduo.enable or false;
        message = "fydetabImage requires boot.loader.fydetabduo.enable = true.";
      }
    ];

    fileSystems."/" = lib.mkDefault {
      device = "/dev/disk/by-label/NIXOS-FYDETAB";
      fsType = "btrfs";
      options = ["x-systemd.growfs"];
    };

    boot.growPartition = lib.mkDefault true;

    systemd.services.growpart.serviceConfig.ExecStart = let
      growpartBin = lib.getExe' pkgs.cloud-utils.guest "growpart";
    in
      lib.mkForce (
        pkgs.writeShellScript "fydetab-growpart" ''
          set -u
          dev=""
          for i in $(seq 1 15); do
            dev=$(findmnt -rno SOURCE / 2>/dev/null | sed 's/\[.*//') || true
            [ -n "$dev" ] && [ -b "$dev" ] && break
            dev=""
            sleep 1
          done
          if [ -z "$dev" ]; then
            echo "root device not resolvable; skipping partition growth" >&2
            exit 0
          fi
          disk=$(lsblk -rno PKNAME "$dev")
          num=$(cat "/sys/class/block/$(basename "$dev")/partition")
          ${growpartBin} "$disk" "$num"
          rc=$?
          [ "$rc" -eq 1 ] && exit 0
          exit "$rc"
        ''
      );

    fileSystems."/snapshots" = lib.mkIf (cfg.snapshots.enable) {
      device = "/dev/disk/by-label/NIXOS-FYDETAB";
      fsType = "btrfs";
      options = ["subvolid=5"];
    };

    environment.systemPackages = lib.mkIf (cfg.snapshots.enable) [
      pkgs.fydetab-snapshot
    ];

    fileSystems."/boot" = lib.mkDefault {
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
    };

    systemd.services.register-nix-paths = {
      description = "Register Nix store paths from the image manifest";
      unitConfig = {
        DefaultDependencies = false;
        ConditionPathExists = "/nix-path-registration";
      };
      wantedBy = ["sysinit.target"];
      before = [
        "sysinit.target"
        "shutdown.target"
        "nix-daemon.socket"
        "nix-daemon.service"
      ];
      after = ["local-fs.target"];
      conflicts = ["shutdown.target"];
      restartIfChanged = false;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${lib.getExe' config.nix.package.out "nix-store"} --load-db < /nix-path-registration

        touch /etc/NIXOS
        ${lib.getExe' config.nix.package.out "nix-env"} -p /nix/var/nix/profiles/system --set /run/current-system

        rm -f /nix-path-registration
      '';
    };

    system.build.image = let
      inherit
        (config.hardware.fydetabduo.bootchain)
        idblock
        uboot
        resource
        ;
    in
      pkgs.callPackage ../../lib/make-fydetab-image.nix {
        toplevel = config.system.build.toplevel;
        bootAssets = config.system.build.fydetabBootAssets;
        idblockBlob = idblock;
        ubootBlob = uboot;
        resourceBlob = resource;
        inherit (cfg) compress;
      };
  };
}
