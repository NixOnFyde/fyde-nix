# fyde-nix - NixOS for the FydeTab Duo [![Build & release image](https://github.com/NixOnFyde/fyde-nix/actions/workflows/ci.yml/badge.svg)](https://github.com/NixOnFyde/fyde-nix/actions/workflows/ci.yml)

Nix flake for the [FydeTab Duo](https://fydetabduo.com/) — Fyde Innovation's open-source RK3588S hackable tablet. The default image runs NixOS with a labwc-based desktop shell.

<!-- toc -->

- [fyde-nix - NixOS for the FydeTab Duo](#fyde-nix---nixos-for-the-fydetab-duo)
  - [Feature status](#feature-status)
    - [Hardware](#hardware)
  - [Docs](#docs)

<!-- /toc -->

> [!CAUTION]
> This is an independent project under the MIT license, and is not endorsed in any way by Fyde Innovations. Irrespective of this, while the utmost caution has been undertaken (including the author testing all builds on their own device first), things can and will break. By continuing, you are acknowledging the possibility of said happenings, and agree that adverse outcomes do not fall on us. That being said, we will always try to help where we can.

> [!TIP]
> As long as you can enter MASKROM or LOADER mode — all can be restored. And, considering the amount of mistakes I made when making this flake — it's really, really hard to stop those modes from working — even if it seems all hope is lost.

## Feature status

### Hardware

Working:

- Accelerometer
- Audio with and without wired headphones
- Bluetooth
- Brightness and volume keys (with OSD)
- Camera
- Deep suspend / resume
- GPU
- HiDPI portrait panel
- Power button - short press suspend, long press power off
- Touchscreen and stylus in any orientation (respecting auto-rotate)
- USB-C DisplayPort / HDMI
- WiFi
- wlroots compositors auto-rotate (greeter defaults to landscape however for ease of use)

## Docs

Coming soon™ — will be pushed within 24 hours of initial commit.
