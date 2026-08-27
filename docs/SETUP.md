# Setup

<!-- toc -->
- [Setup](#setup)
  - [Installing via microSD](#installing-via-microsd)
  - [Installing straight to eMMC](#installing-straight-to-emmc)
  - [Default configuration](#default-configuration)
  - [Updating](#updating)
<!-- /toc -->

> [!IMPORTANT]
> We use the original U-Boot, and not UEFI boot. So, make sure the image installed before installing is one that uses the original U-Boot. If you are not sure, please re-flash the original FydeOS. For example, if you use any of the Arch-based images, they use UEFI boot not U-Boot, so you must first do what is aforementioned.

No matter the installation method, please download the [latest release](https://github.com/NixOnFyde/fyde-nix/releases/latest) image parts. Then run the following:

```sh
cat fydetab-duo-nixos.img.zst.part-a* > fydetab-duo-nixos.img.zst # Combines all parts into one file
zstd -d fydetab-duo-nixos.img.zst # Decompresses the image
```

## Installing via microSD

If you are installing to microSD to test, you must run the following command to flash the image to your microSD, where `/dev/sdX` is your microSD:

```sh
sudo dd if=fydetab-duo-nixos.img of=/dev/sdX bs=4M conv=fsync status=progress
```

> [!CAUTION]
> `dd` does not ask before overwriting a disk, and the image will not boot if you flash the wrong one. Double-check `/dev/sdX` with `lsblk` first!

You should then:

1. Make sure your Fydetab Duo is turned off.
2. Plug in the microSD to your Fydetab Duo.
3. Turn the Fydetab Duo on, and it will automatically boot from the microSD.

You will then be able to use NixOS on the Fydetab Duo!

- The default username is `user`, password `fydetab`.
- If you are planning to install to eMMC after testing, you must do this before your first rebuild. This is because while we package tools such as `fydetab-install-to-emmc` to clone the running system to eMMC, the shipped configuration in `/etc/nixos` disables them - so unless you re-enable `hardware.fydetabduo.installer-tools.enable`, they will be gone after a rebuild.

When you are satisfied to install to eMMC, do the following:

1. Close down any apps that might be writing data to the microSD card.
2. Open Alacritty (Mod+Return) and type `fydetab-install-to-emmc`.
3. It will automatically detect the eMMC - just accept all prompts!
4. Give it about 5-10 minutes to run - even if it looks like it's hanging, it's not!
5. When it has exited, turn off your Fydetab Duo.
6. Remove the microSD from your Fydetab Duo.
7. Turn the Fydetab Duo, and it will automatically boot from eMMC.

Congratulations, you've successfully got NixOS running from your Fydetab Duo's internal storage 🎉!

## Installing straight to eMMC

As this process is identical to the official images (unlike via microSD - as we provide some installer tools there), please follow the official [Flashing the Fydetab Duo](https://wiki.fydetabduo.com/flashing_the_fydetab_duo) documentation - just of course replace the image file with the one we provide!

## Default configuration

No matter the installation method, in `/etc/nixos` you will find a configuration that mirrors the image (with the exception of `hardware.fydetabduo.installer-tools.enable` being false). This configuration can also be found under the [`modules/image/default-config`](https://github.com/NixOnFyde/fyde-nix/tree/main/modules/image/default-config) path of this repository. All possible options are documented extremely well both in said file and the flake, so no more explanation will be provided here. If you have any questions, feel free to ping **@skifli** in the [official FydeOS discord](https://discord.com/invite/sgjZDvuhnh)!

As well as this, we provide a Cachix cache that is automatically setup. This means that you never need to compile the kernel, etc, and rebuilds usually take less than a minute!

## Updating

Just update the flake input, and rebuid! `fydetab-update` is another tool we provide to make updating more seamless - it will only update if you are behind the latest TAGGED release, so rest assured all your updates will have been pre-tested and verified!

```sh
sudo fydetab-update
sudo nixos-rebuild switch
```

You also never need to reinstall. Every switch will refresh the ESP assets, and the btrfs root works with `fydetab-snapshot` for pre-update snapshots and rollback (this device has no U-Boot generation menu).
