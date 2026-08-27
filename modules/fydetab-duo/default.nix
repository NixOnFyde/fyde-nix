{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.hardware.fydetabduo;
in
{
  imports = [
    ./boot-loader.nix
    ./suspend.nix
    ./bluetooth.nix
    ./display-fix.nix
    ./es8388-audio.nix
    ./input.nix
    ./sensors.nix
    ./tablet-mode.nix
    ./wifi-regdom.nix
    ./qol.nix
    ./desktop.nix
    ./shell
  ];

  options.hardware.fydetabduo = {
    enable = lib.mkEnableOption "FydeTab Duo (RK3588S tablet) support";

    installer-tools.enable = lib.mkEnableOption ''
      interactive installation tools (fydetab-install-to-emmc and
      fydetab-update-bootchain). Off by default so personal flakes do not
      contain them; however the built images enable this so flashable
      images include the installer.
    '';

    touchscreen.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Load the vendor himax touch driver and install its calibration data
        and firmware.
      '';
    };

    bootchain.idblock = lib.mkOption {
      type = lib.types.path;
      default = ../../blobs/bootchain/idblock.bin;
      defaultText = lib.literalMD "vendored `blobs/bootchain/idblock.bin`";
      description = ''
        idblock.bin written to LBA 64 of images (DDR init + SPL). Defaults
        to the vendored blob; blobs/bootchain/PROVENANCE.md explains more.
      '';
    };

    bootchain.uboot = lib.mkOption {
      type = lib.types.path;
      default = ../../blobs/bootchain/uboot.img;
      defaultText = lib.literalMD "vendored `blobs/bootchain/uboot.img`";
      description = ''
        uboot.img written to LBA 16384 (U-Boot FIT including the
        deep-suspend-capable BL31).
      '';
    };

    bootchain.resource = lib.mkOption {
      type = lib.types.path;
      default = ../../blobs/bootchain/resource.img;
      defaultText = lib.literalMD "vendored `blobs/bootchain/resource.img`";
      description = "resource.img written to LBA 24580 (splash logos).";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPackages = pkgs.linuxPackages_fydetab;

    boot.kernelParams = [
      "console=ttyFIQ0,1500000n8"
      "console=tty1"
      "quiet"
    ];
    boot.consoleLogLevel = lib.mkDefault 3;

    boot.kernelModules = [
      "dhd"
      "panthor"
    ]
    ++ lib.optionals cfg.touchscreen.enable [ "himax_tp" ]
    ++ lib.optionals cfg.sensors.enable [ "mh248-fyde" ];

    boot.initrd.includeDefaultModules = false;
    boot.initrd.availableKernelModules = lib.mkForce [
      "mmc_block"
      "btrfs"
    ];

    hardware.enableRedistributableFirmware = lib.mkDefault true;

    hardware.firmware = [
      pkgs.ap6275p-firmware
    ]
    ++ lib.optionals cfg.touchscreen.enable [ pkgs.himax-firmware ];

    nixpkgs.config.allowUnfreePredicate =
      pkg:
      builtins.elem (lib.getName pkg) [
        "ap6275p-firmware"
        "himax-firmware"
      ];

    hardware.fydetabduo.bluetooth.enable = lib.mkDefault true;
    hardware.fydetabduo.deepSuspend.enable = lib.mkDefault true;
    hardware.fydetabduo.displayInitFix.enable = lib.mkDefault true;
    hardware.fydetabduo.audio.enable = lib.mkDefault true;
    hardware.fydetabduo.sensors.enable = lib.mkDefault true;
    hardware.fydetabduo.autoRegulatoryDomain.enable = lib.mkDefault true;

    nixpkgs.overlays = [
      (import ../../overlays/default.nix)
      (
        final: _prev:
        let
          unstable = inputs.nixpkgs-unstable.legacyPackages.${final.stdenv.hostPlatform.system};
        in
        {
          labwc = unstable.labwc;
        }
      )
    ];

    environment.systemPackages =
      let
        blobWrap =
          p:
          pkgs.runCommand ("fydetab-" + baseNameOf p) { } ''
            cp ${p} $out
          '';
        bootchainBlobs = builtins.mapAttrs (_: blobWrap) {
          inherit (cfg.bootchain) idblock uboot resource;
        };
      in
      lib.optionals cfg.installer-tools.enable [
        (pkgs.fydetab-install-to-emmc.override bootchainBlobs)

        (pkgs.fydetab-update-bootchain.override bootchainBlobs)
      ];
  };
}
