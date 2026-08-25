{
  lib,
  pkgs,
  toplevel,
  bootAssets,
  idblockBlob,
  ubootBlob,
  resourceBlob,
  rootLabel ? "NIXOS-FYDETAB",
  espLabel ? "ESP",
  compress ? true,
}:
let
  sectorSize = 512;
  fwStartSector = 64;
  fwEndSector = 65535;
  espStartSector = 65536;
  espEndSector = 1114111;
  rootStartSector = 1114112;

  idblockLba = 64;
  ubootLba = 16384;
  resourceLba = 24580;

  espSizeMiB = builtins.div ((espEndSector - espStartSector + 1) * sectorSize) (1024 * 1024);

  closureInfo = pkgs.buildPackages.closureInfo { rootPaths = [ toplevel ]; };

  rootBtrfs = pkgs.stdenvNoCC.mkDerivation {
    name = "btrfs-fs.img";
    nativeBuildInputs = with pkgs; [ btrfs-progs ];

    buildCommand = ''
      mkdir -p rootImage/nix/store

      for p in $(cat ${closureInfo}/store-paths); do
        cp -R --preserve=timestamps,mode "$p" rootImage/nix/store/
      done

      cp ${closureInfo}/registration rootImage/nix-path-registration

      # Seed runtime dirs that the greeter needs before first activation.
      # systemd-tmpfiles creates these on boot, but the greeter starts
      # before tmpfiles has finished on a fresh image.
      mkdir -p rootImage/var/{lib,log}/regreet
      mkdir -p rootImage/tmp/.X11-unix

      # FHS essentials the seed tree omits. /var/run -> /run is required by
      # openssh (privsep chroot) and many daemons; /var/empty is openssh's
      # AuthorizedKeysFile directory.
      ln -s /run rootImage/var/run
      mkdir -p rootImage/var/empty
      chmod 0755 rootImage/var/empty

      # Make sure the root directory is owned by root so systemd-tmpfiles
      # does not refuse to process rules due to "unsafe path transition"
      # from a non-root-owned / to system directories.
      chown -hR 0:0 rootImage

      sizeKiB=$(( $(du -sk rootImage | cut -f1) * 5 / 4 + 262144 ))
      truncate -s "''${sizeKiB}K" btrfs-fs.img

      mkfs.btrfs --rootdir rootImage --shrink -L ${rootLabel} btrfs-fs.img
      mv btrfs-fs.img $out
    '';
  };
in
pkgs.stdenvNoCC.mkDerivation {
  name = "fydetab-duo-nixos.img${lib.optionalString compress ".zst"}";

  nativeBuildInputs = with pkgs; [
    gptfdisk
    dosfstools
    mtools
    util-linux
    zstd
    rk-boot-script
  ];

  passthru = {
    inherit rootBtrfs;
    rootFilesystemLabel = rootLabel;
    espFilesystemLabel = espLabel;
  };

  buildCommand = ''
    img=fydetab-duo-nixos.img

    rootBytes=$(stat -c%s ${rootBtrfs})
    rootMiB=$(( (rootBytes + 1024*1024 - 1) / 1024 / 1024 ))
    totalMiB=$(( ${toString rootStartSector} * ${toString sectorSize} / 1024 / 1024 + rootMiB + 8 ))
    echo "image: ${toString espSizeMiB} MiB ESP + $rootMiB MiB root => $totalMiB MiB total"

    truncate -s "$totalMiB"M "$img"

    sgdisk -a 1 \
      -n "1:${toString fwStartSector}:${toString fwEndSector}" \
         -c 1:FW -t 1:8300 \
      -n "2:${toString espStartSector}:${toString espEndSector}" \
         -c 2:${espLabel} -t 2:ef00 \
      -n "3:${toString rootStartSector}:0" \
         -c 3:ROOTFS -t 3:8300 \
      -A 2:set:2 \
      "$img" > /dev/null
    sgdisk -p "$img"

    attrWord=$(od -An -tu8 \
      -j $(( ${toString sectorSize} * 2 + 128 * (2 - 1) + 48 )) -N 8 "$img" | tr -d ' ')
    [ "$attrWord" -eq 4 ] || {
      echo "!! ESP lacks the legacy_boot attribute bit (attr word: $attrWord)" >&2; exit 1; }

    blob() { dd if="$1" of="$img" bs=${toString sectorSize} seek="$2" conv=notrunc,fdatasync status=none; }
    blob ${idblockBlob}  ${toString idblockLba}
    blob ${ubootBlob}    ${toString ubootLba}
    blob ${resourceBlob} ${toString resourceLba}

    resEnd=$(( ${toString resourceLba} + ( $(stat -c%s ${resourceBlob}) + ${toString sectorSize} - 1 ) / ${toString sectorSize} ))
    [ "$resEnd" -lt ${toString espStartSector} ] || {
      echo "!! bootloader region ends at LBA $resEnd, overlapping the ESP" >&2; exit 1; }

    esp=esp.img
    truncate -s "${toString espSizeMiB}M" "$esp"
    mkfs.vfat -F 32 -n ${espLabel} "$esp" > /dev/null

    mmd    -i "$esp" ::/dtbs ::/dtbs/rockchip
    sed "s|@INIT@|${toplevel}|g" ${bootAssets.bootCmd} > boot.cmd
    rk-mkimage boot.cmd boot.scr "NixOS FydeTab Duo"
    mcopy  -i "$esp" boot.scr  ::/boot.scr
    mcopy  -i "$esp" boot.cmd  ::/boot.cmd
    mcopy  -i "$esp" ${bootAssets.kernelImage} ::/vmlinuz-fydetab
    mcopy  -i "$esp" ${bootAssets.initrd}   ::/initramfs-fydetab.img
    mcopy  -i "$esp" ${bootAssets.dtb}      ::/dtbs/rockchip/rk3588s-fydetab_duo.dtb

    dd if="$esp" of="$img" bs=${toString sectorSize} seek=${toString espStartSector} \
      conv=notrunc,fdatasync status=none

    echo "writing root filesystem (${toString rootStartSector} LBA offset)"
    dd if=${rootBtrfs} of="$img" bs=${toString sectorSize} \
      seek=${toString rootStartSector} conv=notrunc,fdatasync status=none

    ${lib.optionalString compress ''
      zstd -T$NIX_BUILD_CORES --rm "$img"
      mv "$img.zst" $out
    ''}
    ${lib.optionalString (!compress) ''
      mv "$img" $out
    ''}
  '';
}
