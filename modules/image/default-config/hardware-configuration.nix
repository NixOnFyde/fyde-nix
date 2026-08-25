# This file contains hardware-specific filesystem and boot layout for the FydeTab Duo.
# It matches the partition table produced by the image builder.
# YOU GENERALLY DO NOT NEED TO EDIT THIS FILE - IF YOU ARE BE CAREFUL.
{ ... }:

{
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS-FYDETAB";
    fsType = "btrfs";
    options = [ "x-systemd.growfs" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  fileSystems."/snapshots" = {
    device = "/dev/disk/by-label/NIXOS-FYDETAB";
    fsType = "btrfs";
    options = [ "subvolid=5" ];
  };

  boot.growPartition = true;
}
