# fyde-nix - NixOS for the FydeTab Duo

[![Build & release image](https://github.com/NixOnFyde/fyde-nix/actions/workflows/ci.yml/badge.svg)](https://github.com/NixOnFyde/fyde-nix/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

<!-- toc -->

- [fyde-nix - NixOS for the FydeTab Duo](#fyde-nix---nixos-for-the-fydetab-duo)
  - [Quick start](#quick-start)
  - [Documentation](#documentation)
  - [Repository layout](#repository-layout)
  - [Licensing](#licensing)

<!-- /toc -->

Nix flake for the [FydeTab Duo](https://fydetabduo.com/) — Fyde Innovation's open-source RK3588S hackable tablet. The aim is feature parity with Fyde OS, and the current state is **21/30 (70%)** — [full list](docs/PARITY.md).

> [!CAUTION]
> This is an independent project under the MIT license, and is not endorsed in any way by Fyde Innovations. Irrespective of this, while the utmost caution has been undertaken (including the author testing all builds on their own device first), things can and will break. By continuing, you are acknowledging the possibility of said happenings, and agree that adverse outcomes do not fall on us. That being said, we will always try to help where we can.

> [!TIP]
> As long as you can enter MASKROM or LOADER mode — all can be restored. And, considering the amount of mistakes I made when making this flake — it's really, really hard to stop those modes from working — even if it seems all hope is lost.

## Quick start

Please read [docs/SETUP.md](docs/SETUP.md).

## Documentation

- [docs/BOOT.md](docs/BOOT.md)
- [docs/SETUP.md](docs/SETUP.md)
- [docs/STATUS.md](docs/STATUS.md)
- [docs/PARITY.md](docs/PARITY.md)

## Repository layout

```
blobs/bootchain/     boot ROM blobs with provenance notes
pkgs/                kernel, firmware, and tool packages
modules/fydetab-duo/ NixOS modules (hardware.fydetabduo.* options)
modules/image/       image builder module (fydetabImage.enable)
overlays/            nixpkgs overlay adding linuxPackages_fydetab etc
lib/                 image assembly
scripts/             small maintenance helpers (TOC regeneration, ...)
docs/                everything we learnt while making this flake!
```

## Licensing

MIT, see [LICENSE](LICENSE). The boot chain blobs are redistributable firmware owned by their authors (Rockchip/FydeOS); see [blobs/bootchain/PROVENANCE.md](blobs/bootchain/PROVENANCE.md).
