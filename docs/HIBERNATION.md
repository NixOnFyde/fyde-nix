# Hibernation (suspend-to-disk)

Suspend-to-disk is set up with an opt-in NixOS module
(`hardware.fydetabduo.hibernation`) that does most of the work for you: it creates
the swapfile if missing, registers it as a swap device, and adds the
`resume=`/`resume_offset=` kernel parameters.

The swapfile must exist **before** you enable the module, because Nix
evaluates `resumeOffset` at build time. Follow these steps in order:

## 1. Create the swapfile and get the resume offset

```console
$ sudo mkdir -p /swap
$ sudo btrfs filesystem mkswapfile -s 12G /swap/swapfile
$ sudo btrfs inspect-internal map-swapfile /swap/swapfile
Physical start:  18292408320
Resume offset:       4465920
```

`Resume offset` (physical start / 4096) is the value to put in
`resumeOffset`.

## 2. Enable the module

```nix
hardware.fydetabduo.hibernation = {
  enable = true;
  resumeOffset = 4465920;  # <- fill in from step 1
};
```

Then rebuild. Kernel parameter `resume=` + `resume_offset=` is taken care
of in early boot and needs no initrd stuff.

## 3. Test

```console
sudo systemctl hibernate
```

After the device powers off, power it on again: it should restore the RAM
image. If resume hangs, the image can always be
discarded by rebooting a second time (as the next boot comes up normally).
