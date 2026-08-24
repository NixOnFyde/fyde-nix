# fyde-nix - NixOS for the FydeTab Duo

Nix flake for the [FydeTab Duo](https://fydetabduo.com/) — Fyde Innovation's open-source RK3588S hackable tablet. Runs NixOS with a labwc-based desktop shell.

<!-- toc -->

- [fyde-nix - NixOS for the FydeTab Duo](#fyde-nix---nixos-for-the-fydetab-duo)
  - [Feature status](#feature-status)
    - [Hardware](#hardware)
    - [Desktop](#desktop)
    - [System](#system)
  - [Docs](#docs)

<!-- /toc -->

> [!CAUTION]
> This is an independent project under the MIT license, and is not endorsed in any way by Fyde Innovations. Irrespective of this, while the utmost caution has been undertaken (including the author testing all builds on their own device first), things can and will break. By continuing, you are acknowledging the possibility of said happenings, and agree that adverse outcomes do not fall on us. That being said, we will always try to help where we can.

> [!TIP]
> As long as you can enter MASKROM or LOADER mode — all can be restored. And, considering the amount of mistakes I made when making this flake — it's really, really hard to stop those modes from working — even if it seems all hope is lost.

## Feature status

### Hardware

| Feature                     | Status | Implementation                                |
| --------------------------- | ------ | --------------------------------------------- |
| GPU (Mali G610)             | ✅     | Panthor kernel module                         |
| WiFi (AP6275P)              | ✅     | dhd driver + Broadcom firmware                |
| Bluetooth (AP6275P)         | ✅     | brcm-patchram-plus loads BCM4362A2 firmware   |
| Touchscreen (Himax HX83102) | ✅     | himax_tp driver + libinput calibration matrix |
| Stylus                      | ✅     | udev calibration + axis tuning via hwdb       |
| Accelerometer (lis2dw12)    | ✅     | iio-sensor-proxy + rot8 auto-rotate           |
| Audio (ES8388)              | ✅     | Speaker + headphone via PipeWire              |
| Brightness keys             | ✅     | brightnessctl via labwc keybinds              |
| Volume keys                 | ✅     | wpctl via labwc keybinds                      |
| Deep suspend/resume         | ✅     | mem_sleep_default=deep + synthetic wake key   |
| USB-C DisplayPort           | ✅     | Alt mode support                              |
| HiDPI portrait panel        | ✅     | kanshi rotates DSI-1 by 270°                  |
| Camera                      | ✅     | Works out of the box                          |
| Fingerprint reader          | ❌     | Not yet implemented                           |

### Desktop

| Feature            | Status | Implementation                                             |
| ------------------ | ------ | ---------------------------------------------------------- |
| Window manager     | ✅     | labwc with FydeTab theming                                 |
| Login manager      | ✅     | regreet under labwc greeter                                |
| App launcher       | ✅     | Vicinae                                                    |
| Terminal           | ✅     | Ghostty                                                    |
| Status bar         | ✅     | Wayle (clock, battery, volume, network, BT, notifications) |
| Browser            | ✅     | LibreWolf                                                  |
| File manager       | ✅     | Thunar                                                     |
| File manager (TUI) | ✅     | Yazi                                                       |
| Clipboard history  | ✅     | Vicinae clipboard provider                                 |
| Screenshots        | ✅     | grim + slurp (Print key)                                   |
| Notifications      | ✅     | Wayle notifications module                                 |
| Polkit agent       | ✅     | Hyprpolkitagent                                            |
| Keyring            | ✅     | GNOME keyring                                              |
| Idle lock          | ✅     | swayidle + swaylock (10 min screen off, 15 min suspend)    |
| Auto-rotate        | ✅     | rot8 reads accelerometer, rotates via wlr-randr            |
| Wallpaper engine   | ✅     | Wayle wallpaper module (fill mode, DSI-1)                  |

### System

| Feature                | Status | Implementation                                                        |
| ---------------------- | ------ | --------------------------------------------------------------------- |
| Boot from SD           | ✅     | Vendor U-Boot to FAT32 ESP to boot.scr to NixOS                       |
| eMMC install           | ✅     | fydetab-install-to-emmc clones live system with rsync                 |
| Boot chain update      | ✅     | fydetab-update-bootchain rewrites idblock/uboot/resource blobs        |
| Btrfs snapshots        | ✅     | fydetab-snapshot create/list/rollback/delete                          |
| NixOS rebuild          | ✅     | nixos-rebuild switch (over SSH or locally)                            |
| WiFi regulatory domain | ✅     | Auto-detected from system timezone                                    |
| Zram swap              | ✅     | zstd compressed                                                       |
| Journal persistence    | ✅     | CoW-disabled /var/log/journal on btrfs                                |
| SSH                    | ✅     | OpenSSH enabled                                                       |
| XDG user dirs          | ✅     | Auto-created per session                                              |
| Nix flakes             | ✅     | Enabled (nix-command + flakes)                                        |
| Home Manager           | ✅     | Shared module for per-user config (vicinae, wayle, ghostty, swayidle) |

## Docs

Coming soon™ — will be pushed within 24 hours of initial commit.
