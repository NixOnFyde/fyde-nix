# Status: feature matrix

<!-- toc -->

- [Status: feature matrix](#status-feature-matrix)
  - [Feature matrix](#feature-matrix)
  - [On-device bring-up checklist](#on-device-bring-up-checklist)
  - [Release gate](#release-gate)

<!-- /toc -->

Last updated: 2026-08-27.

The image boots from internal storage. The columns use:

| Level      | Meaning                                                  |
| ---------- | -------------------------------------------------------- |
| `working`  | checked working on real hardware                         |
| `build`    | built successfully, output checked                       |
| `eval`     | part of the evaluating system closure, nothing built yet |
| `partial`  | works with caveats                                       |
| `untested` | implemented, needs an on-device test                     |
| `broken`   | implemented but known-broken on device                   |
| `dead end` | approach tried and abandoned                             |
| `planned`  | designed but not implemented yet                         |
| `no plans` | not feasible / not applicable                            |

## Feature matrix

| Feature                                                            | Level      | Notes                                                                                                                                           |
| ------------------------------------------------------------------ | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Boot chain (SPL/U-Boot/boot.scr/initrd/stage-2)                    | `working`  | boots to NixOS from SD and eMMC                                                                                                                 |
| Vendor 6.12.43 kernel builds in nixpkgs sandbox                    | `build`    | defconfig-based, ChromeOS-isms undone, broken vendor drivers disabled                                                                           |
| Panthor GPU driver (G610)                                          | `working`  | CSF FW loads; EGL reports Mesa/Panthor and Vulkan sees ARM on device                                                                            |
| Graphical greeter (labwc + ReGreet)                                | `working`  | greeter runs ReGreet under its own labwc with kanshi rotation + calibrated touch/stylus                                                         |
| tty2 autologin shell for debugging                                 | `working`  | Ctrl+Alt+F2 always gives a terminal even when the session dies - use it for journalctl                                                          |
| Himax touchscreen + stylus                                         | `working`  | touch/stylus works; calibration matrices work                                                                                                   |
| AP6275P WiFi (dhd) + firmware                                      | `working`  | NM uses wpa_supplicant backend by default (`hardware.fydetabduo.wifi.backend`); NM pinned to permanent MAC (brcmfmac rejects MAC randomization) |
| Bluetooth BCM4362A2 patchram over ttyS9                            | `working`  | phone connected, media metadata exchange was visible                                                                                            |
| Deep suspend (`mem`) default                                       | `working`  | suspend/resume cycles incl lid-close; touch+wifi survive                                                                                        |
| Wake-screen fix after resume                                       | `untested` | rk805-pwrkey event diff -> uinput inject                                                                                                        |
| Hall sensor (mh248-fyde)                                           | `working`  | lid close suspends the device                                                                                                                   |
| IIO sensors (lis2dw12 accel) mount matrices                        | `working`  | monitor-sensor reports orientation changes matching the physical tilt                                                                           |
| WiFi regulatory domain helper                                      | `eval`     | `hardware.fydetabduo.autoRegulatoryDomain` + `countryCode` option                                                                               |
| WiFi backend (iwd vs wpa_supplicant)                               | `eval`     | `hardware.fydetabduo.wifi.backend` defaults to `wpa_supplicant` (with added WPA3/SAE support)                                                   |
| nftables fragments for firewall/docker                             | `build`    | mirrored from official image fragments                                                                                                          |
| Initrd builds without x86/EFI module stuff                         | `build`    | includeDefaultModules off, btrfs forced                                                                                                         |
| boot.scr generation with inbuilt init                              | `working`  | boots the exact toplevel closure                                                                                                                |
| Flashable image builder                                            | `build`    | GPT + blobs + FAT32 ESP + btrfs root                                                                                                            |
| legacy_boot attribute on ESP                                       | `build`    | verified in image bytes                                                                                                                         |
| Btrfs root + snapshot tooling                                      | `eval`     | fydetab-snapshot create/list/rollback/delete                                                                                                    |
| First-boot growpart + systemd-growfs                               | `working`  | grows the root partition; skips when the disk is already full                                                                                   |
| Audio (ES8388 routing + PipeWire)                                  | `working`  | output audible after mixer enable                                                                                                               |
| SSH daemon                                                         | `working`  | works across many reboots                                                                                                                       |
| nsncd / Name Service Cache Daemon                                  | `working`  | no failures since ownership fixes on the image                                                                                                  |
| eMMC installer command on live system                              | `eval`     | clones running system, same layout                                                                                                              |
| Bootchain in-place updater                                         | `eval`     | fydetab-update-bootchain; read-back-verifies every blob                                                                                         |
| USB-C DisplayPort altmode                                          | `working`  | external display over USB-C hub came up instantly                                                                                               |
| LTE modem (Quectel EM05-G via M.2)                                 | `working`  | module on by default                                                                                                                            |
| MIPI camera                                                        | `working`  | works - verified                                                                                                                                |
| Microphone                                                         | `working`  | verified through browser                                                                                                                        |
| Backlight + battery reporting                                      | `working`  | brightnessctl work; sysfs capacity/charging correct                                                                                             |
| Hardware buttons                                                   | `working`  | volume rocker emits KEY_VOLUMEUP/DOWN (adc-keys); power key wakes; keys linked with wpctl/brightnessctl with wayle                              |
| Fingerprint reader (microarray/madev)                              | `no plans` | madev builds but no FOSS userspace stack exists; would need a RE'd libfprint driver                                                             |
| NPU (RK3588S, 6 TOPS)                                              | `working`  | vendor rknpu driver (built-in), librknnrt runtime; rknn_init + model load confirmed myself                                                      |
| eMMC boot using community imagebuild bootchain + imagebuild layout | `working`  | NixOS boots from internal storage; blobs in `blobs/bootchain/`                                                                                  |
