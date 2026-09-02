# NOTE: This flake pins fyde-nix to a specific commit via flake.lock.
# When updating to your own configuration, you should do one of the following:
#
#   1. Pin to a tag - most stable as commits are tested before being
#      tagged. The recommended option as it helps prevent breakage.
#   2. OR, run `nix flake update fyde-nix` which updates the lock file
#      to latest main HEAD. Only do this if you want the latest bleeding-
#      edge updates, but note untagged commits may not be fully tested
#      and could result in bricking. Not recommended except for testing.
#
# ─────────────────────────────────────────────────────────────────────────────
# MODULAR IMPORTS
# ─────────────────────────────────────────────────────────────────────────────
#
# This config uses the full bundle (fydetabduo), but you can cherry-pick parts:
#
#   BUNDLES:
#     fyde-nix.nixosModules.fydetabduo           -- everything
#     fyde-nix.nixosModules.fydetabduo-hardware  -- no desktop shell
#
#   INDIVIDUAL:
#     fyde-nix.nixosModules.base                 -- kernel + firmware
#     fyde-nix.nixosModules.bluetooth            -- bluetooth
#     fyde-nix.nixosModules.npu                  -- NPU
#     fyde-nix.nixosModules.shell-audio          -- PipeWire
#     ... (see full list in configuration.nix)
#
# Example: hardware only + niri compositor:
#
#   modules = [
#     fyde-nix.nixosModules.base
#     fyde-nix.nixosModules.bluetooth
#     fyde-nix.nixosModules.audio
#     fyde-nix.nixosModules.input
#     fyde-nix.nixosModules.npu
#     fyde-nix.nixosModules.qol
#     fyde-nix.nixosModules.boot-loader
#     ./my-niri-config.nix
#   ];
# ─────────────────────────────────────────────────────────────────────────────
{
  description = "FydeTab Duo nixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    fyde-nix.url = "github:NixOnFyde/fyde-nix";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vicinae.url = "github:vicinaehq/vicinae";
  };

  outputs =
    {
      nixpkgs,
      fyde-nix,
      home-manager,
      vicinae,
      ...
    }@inputs:
    {
      nixosConfigurations.fydetabduo = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {
          inherit inputs;
          fyde-nix = fyde-nix;
        };
        modules = [
          fyde-nix.nixosModules.fydetabduo
          home-manager.nixosModules.home-manager
          vicinae.nixosModules.default
          ./configuration.nix
        ];
      };
    };
}
