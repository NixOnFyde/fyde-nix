# Feature parity with FydeOS

Tracks progress toward full hardware and software feature parity with the
official FydeOS image for the Fydetab Duo. FydeOS v23 (2026-08-20) is the
reference.

<!-- toc -->

- [Feature parity with FydeOS](#feature-parity-with-fydeos)
  - [Summary](#summary)
  - [Hardware features](#hardware-features)
  - [Software features](#software-features)

<!-- /toc -->

## Summary

| Category    | Done   | Total  | Percent |
| ----------- | ------ | ------ | ------- |
| Hardware    | 15     | 16     | 94%     |
| Software    | 7      | 14     | 50%     |
| **Overall** | **22** | **30** | **73%** |

Hardware parity is nearly complete. Software parity is lower because many
FydeOS features are ChromeOS-specific and don't have direct NixOS equivalents — or aren't desired (e.g., proprietary).

## Hardware features

| Feature                     | FydeOS    | fyde-nix   | Status  | Notes                                               |
| --------------------------- | --------- | ---------- | ------- | --------------------------------------------------- |
| Boot from eMMC              | `working` | `working`  | done    | community imagebuild bootchain                      |
| Deep suspend/resume (`mem`) | `working` | `working`  | done    | lid-close, touch and wifi work after                |
| GPU (Panthor + Mesa)        | `working` | `working`  | done    | EGL + Vulkan verified                               |
| WiFi 6 (AP6275P)            | `working` | `working`  | done    | NM iwd backend by default; permanent MAC pin for NM       |
| Bluetooth (BCM4362A2)       | `working` | `working`  | done    | phone connected, media metadata sent                |
| Touch + stylus (Wacom)      | `working` | `working`  | done    | himax touchscreen + stylus, calibration in labwc    |
| LTE modem (Quectel EM05-G)  | `working` | `working`  | done    | kernel + `nm-applet` for tray GUI + Gnome GUI       |
| USB-C DisplayPort           | `working` | `working`  | done    | external display over USB-C hub                     |
| Audio (ES8388 + PipeWire)   | `working` | `working`  | done    | supports wired / wireless headphones, and OSD works |
| Camera (5 MP front)         | `working` | `working`  | done    | confirmed via librewolf testing                     |
| Hall sensor (mh248-fyde)    | `working` | `working`  | done    | lid close suspends                                  |
| IIO sensors (accel)         | `working` | `working`  | done    | lis2dw12, monitor-sensor reports orientation        |
| Volume rocker               | `working` | `working`  | done    | confirmed via OSD                                   |
| Backlight + battery         | `working` | `working`  | done    | brightnessctl + sysfs capacity                      |
| Fingerprint reader          | `working` | `no plans` | blocked | madev builds but no open libfprint driver           |
| NPU (6 TOPS)                | `working` | `working`  | done    | vendor rknpu driver + librknnrt runtime             |

## Software features

| Feature                   | FydeOS              | fyde-nix                                      | Status      | Notes                                                        |
| ------------------------- | ------------------- | --------------------------------------------- | ----------- | ------------------------------------------------------------ |
| Android apps (fyDroid)    | built-in            | —                                             | planned     | ChromeOS-specific container; Waydroid possible future option |
| Auto rotate               | built-in            | `hardware.fydetabduo.sensors.autoRotate`      | done        | Custom module - controlled by wayle                          |
| Auto tablet-mode with OSK | built-in            | `hardware.fydetabduo.tabletMode`              | done        | Custom module - controlled by wayle                          |
| Auto power profiles       | built-in            | `hardware.fydetabduo.shell.power.autoProfile` | done        | Custom option with AC override                               |
| Linux apps (Crostini)     | Debian 12 container | native NixOS                                  | done        | we _are_ Linux; no container needed                          |
| OTA system updates        | built-in            | native NixOS                                  | done        | NixOS uses `nixos-rebuild switch`; essentialy same ease      |
| Vulkan (Panthor)          | experimental        | Mesa 25                                       | done        | `vkcube` verified                                            |
| Screen recording          | built-in            | —                                             | planned     | could add via wf-recorder + pipewire                         |
| Widevine DRM              | sideloadable        | —                                             | not planned | proprietary; conflicts with NixOS philosophy                 |
| VNC server                | built-in            | —                                             | planned     | could add via wayvnc or similar                              |
| Remote desktop            | built-in            | —                                             | planned     | could add via RustDesk or similar                            |
| Chinese IME (fydeRhythm)  | built-in            | —                                             | planned     | can be added via fcitx5 if needed                            |
| Quick Share               | built-in            | —                                             | planned     | Via KDE Connect                                              |
| FydeOS Store              | built-in            | nixpkgs                                       | done        | different model for Nix, but same same                       |
