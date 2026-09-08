# Hibernation (suspend-to-disk)

## 1. Create the swap file

```console
sudo btrfs filesystem mkswapfile -s 12G /swap/swapfile
```

`-s 12G` must be higher than the device's RAM size (FydeTab Duo: 7.7 GiB).

## 2. Capture the resume offset

```console
$ sudo btrfs inspect-internal map-swapfile /swap/swapfile
Physical start:  110365769728
Resume offset:      26944768
```

`Resume offset` (physical start / 4096) is the value you put as the
`resume_offset=` - if the file changes it may change so update the config if you do change it.

## 3. Resultant NixOS configuration

`resume_offset` is the only value Nix cannot make: it denotes where the
file was physically allocated on _your_ disk, and the kernel needs it on the
boot command line, which is generated at build time. Everything else is
declarative however.

```nix
{ pkgs, ... }:
{
  # Create the swapfile on the root filesystem if it is missing.
  systemd.services.create-swapfile = {
    description = "Create btrfs swapfile if absent";
    before = [ "swap.target" ];
    wantedBy = [ "swap.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.btrfs-progs ];
    script = ''
      if [ ! -e /swap/swapfile ]; then
        btrfs filesystem mkswapfile -s 12G /swap/swapfile
      fi
    '';
  };

  swapDevices = [ { device = "/swap/swapfile"; } ];

  # resume= is the block device holding the swap file.
  boot.kernelParams = [
    "resume=PARTUUID=AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    "resume_offset=26944768" # <- fill in from `map-swapfile`, step 2
  ];
}
```

Replace the PARTUUID with the root device's PARTUUID
(`blkid -s PARTUUID /dev/mmcblk0p3`). Kernel-parameter `resume=` + `resume_offset=`
is taken care of in early boot and needs no initrd stuff.

## 4. Test

```console
sudo systemctl hibernate
```

After the device powers off, power it on again: it should restore the RAM
image. If resume hangs, the image can always be
discarded by rebooting a second time (as the next boot comes up normally).
