# fyde-nix - NixOS for the FydeTab Duo

![Kernel: Rockchip 6.12 BSP](https://img.shields.io/badge/Kernel-Rockchip_6.12_BSP-blue) [![Build & release image](https://github.com/NixOnFyde/fyde-nix/actions/workflows/ci.yml/badge.svg)](https://github.com/NixOnFyde/fyde-nix/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

<!-- toc -->

- [fyde-nix - NixOS for the FydeTab Duo](#fyde-nix---nixos-for-the-fydetab-duo)
  - [Quick start](#quick-start)
  - [Modular API](#modular-api)
  - [Documentation](#documentation)
  - [Repository layout](#repository-layout)
  - [Licensing](#licensing)

<!-- /toc -->

Nix flake for the [FydeTab Duo](https://fydetabduo.com/) — Fyde Innovation's open-source RK3588S hackable tablet. The aim is feature parity with Fyde OS, and the current state is **22/30 (73%)** — [full list](docs/PARITY.md).

> [!CAUTION]
> This is an independent project under the MIT license, and is not endorsed in any way by Fyde Innovations. Irrespective of this, while the utmost caution has been undertaken (including the author testing all builds on their own device first), things can and will break. By continuing, you are acknowledging the possibility of said happenings, and agree that adverse outcomes do not fall on us. That being said, we will always try to help where we can.

> [!TIP]
> As long as you can enter MASKROM or LOADER mode — all can be restored. And, considering the amount of mistakes I made when making this flake — it's really, really hard to stop those modes from working — even if it seems all hope is lost.

## Quick start

Please read [docs/SETUP.md](docs/SETUP.md).

## Modular API

fyde-nix provides individual NixOS modules for each feature. Import only what you need:

```nix
# Full bundle (everything)
inputs.fyde-nix.nixosModules.fydetabduo

# Hardware only (no desktop shell)
inputs.fyde-nix.nixosModules.fydetabduo-hardware

# Cherry-pick individual features
inputs.fyde-nix.nixosModules.base
inputs.fyde-nix.nixosModules.bluetooth
inputs.fyde-nix.nixosModules.npu
inputs.fyde-nix.nixosModules.shell-audio
# ... (see full list in modules/fydetab-duo/default.nix)
```

Each feature is guarded by its own enable option, so even with the full bundle on you can turn pieces off:

```nix
hardware.fydetabduo.modem.enable = false;
hardware.fydetabduo.shell.audio.enable = false;
```

Per-user components (wayle, vicinae, swayidle) are Home Manager modules:

```nix
inputs.fyde-nix.homeManagerModules.default     # all
inputs.fyde-nix.homeManagerModules.wayle       # bar only
inputs.fyde-nix.homeManagerModules.swayidle    # lock only
```

See [docs/DESKTOP.md](docs/DESKTOP.md) for the full DE guide.

## Documentation

- [docs/BOOT.md](docs/BOOT.md)
- [docs/SETUP.md](docs/SETUP.md)
- [docs/DESKTOP.md](docs/DESKTOP.md)
- [docs/STATUS.md](docs/STATUS.md)
- [docs/PARITY.md](docs/PARITY.md)

## Repository layout

```
blobs/bootchain/         boot ROM blobs with notes about provenance
pkgs/                    kernel, firmware, and tool pkgs
modules/fydetab-duo/     NixOS modules (each importable on their own)
  base.nix               kernel, firmware, overlays (required by everything)
  bluetooth.nix          AP6275P bluetooth
  suspend.nix            deep suspend (DRAM self-refresh)
  display-fix.nix        fb0 cold-boot fix
  es8388-audio.nix       ES8388 codec routing
  input.nix              touchscreen / stylus udev
  sensors.nix            accelerometer + auto-rotate
  tablet-mode.nix        OSK show/hide on keyboard attach
  wifi-regdom.nix        WiFi regulatory domain
  modem.nix              Quectel EM05-G LTE
  npu.nix                RK3588S NPU driver + librknnrt
  qol.nix                zram, fstrim, earlyoom, etc.
  boot-loader.nix        U-Boot boot.scr generation
  desktop.nix            labwc, regreet, kanshi, keybinds
  shell/                 desktop shell sub-modules
    audio.nix            PipeWire + rtkit
    power.nix            upower + power-profiles-daemon
    security.nix         keyring + polkit agent
    packages.nix         desktop apps & fonts
    desktop.nix          compositor & greeter config
    home/                Home Manager modules
      wayle.nix          status bar
      vicinae.nix        app launcher
      swayidle.nix       idle lock
modules/image/           image builder module (fydetabImage.enable)
overlays/                nixpkgs overlay adding linuxPackages_fydetab etc
lib/                     image assembly
scripts/                 small maintenance helpers (TOC regeneration, ...)
docs/                    everything I learnt while making this flake!
```

## Licensing

MIT, see [LICENSE](LICENSE). The boot chain blobs are redistributable firmware owned by their authors (Rockchip/FydeOS); see [blobs/bootchain/PROVENANCE.md](blobs/bootchain/PROVENANCE.md).
