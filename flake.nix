{
  description = "NixOS for the FydeTab Duo (RK3588S tablet)";

  nixConfig = {
    extra-substituters = [ "https://vicinae.cachix.org" ];
    extra-trusted-public-keys = [ "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc=" ];
  };

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

  inputs.home-manager = {
    url = "github:nix-community/home-manager/master";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  inputs.vicinae.url = "github:vicinaehq/vicinae";

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forSystems = lib.genAttrs systems;
    in
    {

      overlays.default = import ./overlays/default.nix;

      packages = forSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in
        {
          linux-fydetab = pkgs.linux_fydetab;

          ap6275p-firmware = pkgs.ap6275p-firmware;
          himax-firmware = pkgs.himax-firmware;
          brcm-patchram-plus = pkgs.brcm-patchram-plus;
          rk-boot-script = pkgs.rk-boot-script;
          fydetab-wake-activity = pkgs.fydetab-wake-activity;
          fydetab-snapshot = pkgs.fydetab-snapshot;
          fydetab-update = pkgs.fydetab-update;
          fydetab-update-bootchain = pkgs.fydetab-update-bootchain;
        }
        // (
          let
            image = self.nixosConfigurations.example.config.system.build.image;
          in
          if system == "aarch64-linux" then
            {
              inherit image;
              default = image;
            }
          else
            { }
        )
      );

      nixosModules = {
        fydetabduo = ./modules/fydetab-duo;
        fydetabduo-image = ./modules/image/fydetab-duo-image.nix;
        default = self.nixosModules.fydetabduo;
      };

      homeManagerModules.default = ./modules/fydetab-duo/shell/home.nix;

      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {
          inherit inputs;
          nixpkgs-unstable = inputs.nixpkgs-unstable;
          fyde-nix = self;
        };
        modules = [
          self.nixosModules.fydetabduo
          self.nixosModules.fydetabduo-image
          home-manager.nixosModules.home-manager
          inputs.vicinae.nixosModules.default
          ./modules/image/default-config/configuration.nix
          (
            { ... }:
            {
              hardware.fydetabduo.installer-tools.enable = true;
              fydetabImage.enable = true;
              fydetabImage.defaultConfig.enable = true;
              boot.initrd.systemd.emergencyAccess = true;
            }
          )
        ];
      };
    };
}
