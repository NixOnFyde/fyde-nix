{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.boot.loader.fydetabduo;

  bootCmd = pkgs.writeText "fydetab-duo-boot.cmd" ''
    setenv bootpart ${toString cfg.partitionNumbers.esp}
    setenv rootpart ${toString cfg.partitionNumbers.root}
    setenv fdtfile /dtbs/rockchip/rk3588s-fydetab_duo.dtb
    setenv linux_image /vmlinuz-fydetab
    setenv initrd /initramfs-fydetab.img

    part uuid ''${devtype} ''${devnum}:${toString cfg.partitionNumbers.root} root_uuid

    setenv bootargs rootfstype=${cfg.rootFilesystemType} rootwait rw root=PARTUUID=''${root_uuid} init=@INIT@/init ${lib.concatStringsSep " " config.boot.kernelParams}

    load ''${devtype} ''${devnum}:${toString cfg.partitionNumbers.esp} ''${kernel_addr_c} ''${linux_image}
    load ''${devtype} ''${devnum}:${toString cfg.partitionNumbers.esp} ''${fdt_addr_r} ''${fdtfile}
    load ''${devtype} ''${devnum}:${toString cfg.partitionNumbers.esp} ''${ramdisk_addr_r} ''${initrd}

    booti ''${kernel_addr_c} ''${ramdisk_addr_r}:''${filesize} ''${fdt_addr_r}
  '';

  kernelImage = "${config.boot.kernelPackages.kernel}/${config.system.boot.loader.kernelFile}";
  dtb = "${config.boot.kernelPackages.kernel}/dtbs/rockchip/rk3588s-fydetab_duo.dtb";

  installHook = pkgs.writeShellScript "fydetabduo-install-bootloader" ''
    set -euo pipefail

    PATH="${pkgs.coreutils}/bin:${pkgs.gnused}/bin"

    top=$1
    esp=${cfg.mountPath}

    test -d "$esp" || {
      echo "refusing to operate: ${cfg.mountPath} is not mounted (mount your ESP there first)" >&2
      exit 1
    }

    echo "updating FydeTab Duo boot files in $esp..."

    cp "$top/kernel" "$esp/vmlinuz-fydetab.tmp"
    cp "$top/initrd" "$esp/initramfs-fydetab.img.tmp"
    mkdir -p "$esp/dtbs/rockchip"
    cp ${dtb} "$esp/dtbs/rockchip/rk3588s-fydetab_duo.dtb.tmp"
    mv -f "$esp/vmlinuz-fydetab.tmp" "$esp/vmlinuz-fydetab"
    mv -f "$esp/initramfs-fydetab.img.tmp" "$esp/initramfs-fydetab.img"
    mv -f "$esp/dtbs/rockchip/rk3588s-fydetab_duo.dtb.tmp" \
          "$esp/dtbs/rockchip/rk3588s-fydetab_duo.dtb"

    sed "s|@INIT@|$top|g" ${bootCmd} > "$esp/boot.cmd.tmp"
    ${pkgs.rk-boot-script}/bin/rk-mkimage "$esp/boot.cmd.tmp" "$esp/boot.scr.tmp" "NixOS FydeTab Duo"
    mv -f "$esp/boot.scr.tmp" "$esp/boot.scr"
    mv -f "$esp/boot.cmd.tmp" "$esp/boot.cmd"

    sync
    echo "FydeTab Duo boot files updated."
  '';
in
{
  options.boot.loader.fydetabduo = {
    enable = lib.mkOption {
      default = false;
      type = lib.types.bool;
      description = ''
        Whether to configure the FydeTab Duo boot sys (vendor U-Boot +
        FAT32 ESP with boot.scr). Installs kernel, initrd, DTB, and boot
        scripts to the ESP on every activation.
      '';
    };

    mountPath = lib.mkOption {
      type = lib.types.str;
      default = "/boot";
      description = "Where the ESP (partition 2, FAT32) is mounted.";
    };

    partitionNumbers = {
      esp = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "GPT partition number of the ESP. Must match images built by this flake.";
      };
      root = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "GPT partition number of the root filesystem. Must match images built by this flake.";
      };
    };

    rootFilesystemType = lib.mkOption {
      type = lib.types.enum [
        "ext4"
        "btrfs"
      ];
      default = "btrfs";
      description = "fstype passed as rootfstype=/rootflags= on the kernel cmdline. Images built by this flake use btrfs (snapshots); ext4 is available if wanted.";
    };

    btrfsSubvolume = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "@";

      description = ''
        When rootFilesystemType=btrfs: subvolume mounted as root (passed as
        rootflags=subvol=<name>). Leave null to boot the filesystem's
        *default* subvolume (what this flake's images ship), so snapshots can
        be rolled back by changing the default subvolume.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.boot.isContainer;
        message = "boot.loader.fydetabduo is not available in NixOS containers.";
      }
      {
        assertion =
          cfg.rootFilesystemType != "btrfs" || cfg.btrfsSubvolume == null || cfg.btrfsSubvolume != "";
        message = "boot.loader.fydetabduo.btrfsSubvolume must not be empty.";
      }
    ];

    boot.loader.external.enable = true;
    boot.loader.external.installHook = installHook;

    boot.loader.grub.enable = false;
    boot.loader.systemd-boot.enable = false;

    fileSystems.${cfg.mountPath} = lib.mkDefault {
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
    };

    boot.kernelParams =
      let
        subvol = lib.optionalString (cfg.btrfsSubvolume != null) "subvol=${cfg.btrfsSubvolume}";
      in
      lib.mkAfter (
        lib.optionals (cfg.rootFilesystemType == "btrfs" && cfg.btrfsSubvolume != null) [
          "rootflags=${subvol}"
        ]
      );

    system.build.fydetabBootAssets = {
      inherit bootCmd;
      kernelImage = kernelImage;
      initrd = "${config.system.build.initialRamdisk}/initrd";
      inherit dtb;
    };
  };
}
