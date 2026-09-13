# Hibernation (suspend-to-disk)

Suspend-to-disk is set up with an opt-in NixOS module
(`hardware.fydetabduo.hibernation`) that handles the plumbing: it creates
the swapfile if missing, registers it as a swap device, and adds the
`resume=`/`resume_offset=` kernel parameters. All you provide is the one
value Nix cannot know — the physical `resume_offset` of the swapfile.

## 1. Enable the module

```nix
hardware.fydetabduo.hibernation = {
  enable = true;
  # swapSize = "12G";   # optional; must exceed RAM (7.7 GiB on the Duo)
  resumeOffset = null;  # <-- fill from step 2
};
```

`resume=` defaults to the root device (the swapfile lives on the root
filesystem), and the swapfile is created declaratively at boot if absent.

## 2. Capture the resume offset

Once the system has booted with the module enabled (so the swapfile
exists), run:

```console
$ sudo btrfs inspect-internal map-swapfile /swap/swapfile
Physical start:  110365769728
Resume offset:      26944768
```

`Resume offset` (physical start / 4096) is the value to put in
`resumeOffset`. If the swapfile is ever recreated the offset may change,
so re-run this after changing `swapSize`.

```nix
hardware.fydetabduo.hibernation = {
  enable = true;
  resumeOffset = 26944768; # <- fill in from `map-swapfile`, step 2
};
```

Then rebuild. Kernel-parameter `resume=` + `resume_offset=` is taken care
of in early boot and needs no initrd stuff.

## 3. Test

```console
sudo systemctl hibernate
```

After the device powers off, power it on again: it should restore the RAM
image. If resume hangs, the image can always be
discarded by rebooting a second time (as the next boot comes up normally).