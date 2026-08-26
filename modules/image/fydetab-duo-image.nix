{
  config,
  lib,
  pkgs,
  fyde-nix ? null,
  ...
}:
let
  cfg = config.fydetabImage;
in
{
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

    defaultConfig = {
      enable = lib.mkEnableOption ''
        shipping an exemplar configuration in the image.

        When enabled the image contains a configuration that reproduces
        the exact system the image was built from, so rebuilding without
        any file changes should change nothing except what's detailed below:

        It specifically omits fydetabImage.enable (you shouldn't need to
        rebuild the image on-device) and boot.initrd.systemd.emergencyAccess
        (which is for debugging and it should not stay on by default).
      '';
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
      options = [ "x-systemd.growfs" ];
    };

    boot.growPartition = lib.mkDefault true;

    systemd.services.growpart.serviceConfig.ExecStart =
      let
        growpartBin = lib.getExe' pkgs.cloud-utils.guest "growpart";
        # The image's GPT only spans the (shrunk) image size; when flashed to
        # a larger disk (bigger SD, or the inbuilt 256G eMMC) the backup GPT
        # sits at the end, so growpart sees no free space. Relocate it to the
        # actual end of the disk first (does nothing when it's already correct).
        sgdiskBin = lib.getExe' pkgs.gptfdisk "sgdisk";
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
          disk="/dev/$disk"
          num=$(cat "/sys/class/block/$(basename "$dev")/partition")
          ${sgdiskBin} -e "$disk" \
            || echo "sgdisk -e failed; continuing anyway" >&2
          ${growpartBin} "$disk" "$num"
          rc=$?
          [ "$rc" -eq 1 ] && exit 0
          exit "$rc"
        ''
      );

    fileSystems."/snapshots" = lib.mkIf (cfg.snapshots.enable) {
      device = "/dev/disk/by-label/NIXOS-FYDETAB";
      fsType = "btrfs";
      options = [ "subvolid=5" ];
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
      description = "Register Nix store paths from the image manifest and activate the system";
      unitConfig = {
        DefaultDependencies = false;
        ConditionPathExists = "/nix-path-registration";
      };
      wantedBy = [ "sysinit.target" ];
      before = [
        "sysinit.target"
        "shutdown.target"
        "nix-daemon.socket"
        "nix-daemon.service"
      ];
      after = [ "local-fs.target" ];
      conflicts = [ "shutdown.target" ];
      restartIfChanged = false;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${lib.getExe' config.nix.package.out "nix-store"} --load-db < /nix-path-registration

        touch /etc/NIXOS
        ${lib.getExe' config.nix.package.out "nix-env"} -p /nix/var/nix/profiles/system --set /run/current-system

        # Run the full NixOS activation so /etc, /var, tmpfiles, etc.
        # are set up before services (including greetd) start.
        /run/current-system/activate

        rm -f /nix-path-registration
      '';
    };

    system.build.image =
      let
        inherit (config.hardware.fydetabduo.bootchain)
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

    # EXEMPLAR /etc/nixos config
    #
    # When defaultConfig.enable is set, the image ships a config
    # under /etc/nixos so that a rebuild without touching them
    # reproduces the exact same system.
    environment.etc = lib.mkIf cfg.defaultConfig.enable {
      "nixos/configuration.nix".source = ./default-config/configuration.nix;
      "nixos/hardware-configuration.nix".source = ./default-config/hardware-configuration.nix;

      # flake.nix - pinned to the commit recorded in flake.lock.
      "nixos/flake.nix".source = ./default-config/flake.nix;

      # flake.lock - auto-generated from the repo's own lock file.
      # The shipped flake has the same inputs (nixpkgs, nixpkgs-unstable,
      # home-manager, vicinae) and fyde-nix. So, we patch the root node and
      # add the fyde-nix entry using jq so the lock stays in sync with the
      # build environment without any manual stuff.
      "nixos/flake.lock".source =
        let
          fydeRev = if builtins.isAttrs fyde-nix then fyde-nix.rev or "main" else "main";
          fydeHash = if builtins.isAttrs fyde-nix then fyde-nix.narHash or "" else "";
          fydeLastModified = if builtins.isAttrs fyde-nix then fyde-nix.lastModifiedDate or 0 else 0;
        in
        pkgs.runCommand "flake.lock" { nativeBuildInputs = [ pkgs.jq ]; } ''
          cp ${../../flake.lock} $out
          jq \
            --arg rev "${fydeRev}" \
            --arg hash "${fydeHash}" \
            --arg lm "${toString fydeLastModified}" \
            '
            .nodes.root.inputs["fyde-nix"] = "fyde-nix"
            | .nodes["fyde-nix"] = {
                "locked": {
                  "lastModified": ($lm | tonumber),
                  "narHash": $hash,
                  "owner": "NixOnFyde",
                  "repo": "fyde-nix",
                  "rev": $rev,
                  "type": "github"
                },
                "original": {
                  "owner": "NixOnFyde",
                  "repo": "fyde-nix",
                  "type": "github"
                }
              }
            ' "$out" > "$out.tmp" && mv "$out.tmp" "$out"
        '';
    };

  };
}
