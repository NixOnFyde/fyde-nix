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
          librknnrt = pkgs.librknnrt;
          brcm-patchram-plus = pkgs.brcm-patchram-plus;
          rk-boot-script = pkgs.rk-boot-script;
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
        # ── Convenience bundle ──────────────────────────────────────────
        # Everything: base + all hardware + desktop shell + home-manager.
        fydetabduo = ./modules/fydetab-duo;
        default = self.nixosModules.fydetabduo;

        # Hardware only: base + all hardware features, no desktop shell.
        # Use this when you use your own compositor (niri, sway, GNOME…).
        fydetabduo-hardware = ./modules/fydetab-duo/hardware.nix;

        # ── Core ─────────────────────────────────────────────────────────
        # Kernel, firmware, overlays. Required by everything else.
        base = ./modules/fydetab-duo/base.nix;

        # ── Hardware features ────────────────────────────────────────────
        # Each is importable on its own. Requires `base` above.
        bluetooth = ./modules/fydetab-duo/bluetooth.nix;
        suspend = ./modules/fydetab-duo/suspend.nix;
        display-fix = ./modules/fydetab-duo/display-fix.nix;
        audio = ./modules/fydetab-duo/es8388-audio.nix;
        input = ./modules/fydetab-duo/input.nix;
        sensors = ./modules/fydetab-duo/sensors.nix;
        tablet-mode = ./modules/fydetab-duo/tablet-mode.nix;
        wifi = ./modules/fydetab-duo/wifi-regdom.nix;
        modem = ./modules/fydetab-duo/modem.nix;
        npu = ./modules/fydetab-duo/npu.nix;
        qol = ./modules/fydetab-duo/qol.nix;
        boot-loader = ./modules/fydetab-duo/boot-loader.nix;

        # ── Desktop shell ────────────────────────────────────────────────
        # labwc compositor, greeter, kanshi, keybinds, regreet CSS.
        desktop = ./modules/fydetab-duo/desktop.nix;

        # Shell catch-all: master toggle + all sub-modules below.
        shell = ./modules/fydetab-duo/shell;

        # Shell sub-modules (each toggleable on its own).
        shell-desktop = ./modules/fydetab-duo/shell/desktop.nix;
        shell-packages = ./modules/fydetab-duo/shell/packages.nix;
        shell-audio = ./modules/fydetab-duo/shell/audio.nix;
        shell-power = ./modules/fydetab-duo/shell/power.nix;
        shell-security = ./modules/fydetab-duo/shell/security.nix;

        # ── Image builder ────────────────────────────────────────────────
        fydetabduo-image = ./modules/image/fydetab-duo-image.nix;
      };

      homeManagerModules = {
        # All per-user components (wayle, vicinae, swayidle, wl-clip-persist).
        default = ./modules/fydetab-duo/shell/home.nix;

        # Individual per-user modules.
        wayle = ./modules/fydetab-duo/shell/home/wayle.nix;
        vicinae = ./modules/fydetab-duo/shell/home/vicinae.nix;
        swayidle = ./modules/fydetab-duo/shell/home/swayidle.nix;
      };

      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {
          inherit inputs;
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
