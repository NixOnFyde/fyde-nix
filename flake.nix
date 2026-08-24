{
  description = "NixOS for the FydeTab Duo (RK3588S tablet)";

  nixConfig = {
    extra-substituters = [ "https://vicinae.cachix.org" ];
    extra-trusted-public-keys = [ "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc=" ];
  };

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

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

      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          self.nixosModules.fydetabduo
          self.nixosModules.fydetabduo-image
          home-manager.nixosModules.home-manager
          inputs.vicinae.nixosModules.default
          (
            {
              lib,
              pkgs,
              ...
            }:
            {
              hardware.fydetabduo.enable = true;
              hardware.fydetabduo.landscape.enable = true;

              hardware.fydetabduo.shell.enable = true;

              hardware.fydetabduo.installer-tools.enable = true;
              boot.loader.fydetabduo.enable = true;
              fydetabImage.enable = true;

              programs.vicinae.input-server.enable = true;

              nixpkgs.config.allowUnfreePredicate =
                pkg:
                builtins.elem (lib.getName pkg) [
                  "ap6275p-firmware"
                  "himax-firmware"
                ];

              networking.hostName = "fydetabduo";

              console.keyMap = "uk";
              environment.sessionVariables.XKB_DEFAULT_LAYOUT = "gb";
              networking.networkmanager.enable = true;

              networking.modemmanager.enable = true;

              users.users.user = {
                isNormalUser = true;
                extraGroups = [
                  "wheel"
                  "networkmanager"
                ];
                initialPassword = "fydetab";
              };

              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                sharedModules = [ ./modules/fydetab-duo/shell/home.nix ];
                extraSpecialArgs = { inherit inputs; };
                users.user = {
                  home.stateVersion = "26.05";

                  home.enableNixpkgsReleaseCheck = false;
                };
              };

              boot.initrd.systemd.emergencyAccess = true;

              services.openssh.enable = true;

              networking.firewall.allowedTCPPorts = [ 22 ];

              environment.systemPackages = with pkgs; [
                adwaita-icon-theme
                alsa-utils
                btop
                evtest
                fastfetch
                fydetab-wallpaper
                iio-sensor-proxy
                kanshi
                libinput
                mesa-demos
                papirus-icon-theme
                pulseaudio
                usb-modeswitch
                vulkan-tools
                xdg-user-dirs
              ];

              fonts.packages = with pkgs; [
                noto-fonts
                noto-fonts-color-emoji
                nerd-fonts.symbols-only
              ];

              environment.pathsToLink = [ "/share/backgrounds" ];

              security.rtkit.enable = true;
              services.pipewire = {
                enable = true;
                alsa.enable = true;
                pulse.enable = true;
              };

              programs.labwc.enable = true;
              programs.regreet.enable = true;

              system.stateVersion = "26.05";
            }
          )
        ];
      };
    };
}
