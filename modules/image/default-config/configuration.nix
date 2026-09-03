# EXEMPLAR CONFIGURATION
#
# Rebuilding with this file untouched reproduces the same system the
# image was built from, except for the fact that installer-tools
# is not enabled. To customise, edit here or add a second file and
# import it here. Or, make your own from scratch.
#
# ─────────────────────────────────────────────────────────────────────────────
# MODULAR API
# ─────────────────────────────────────────────────────────────────────────────
#
# fyde-nix provides individual NixOS modules for each feature. Import only
# what you need in your flake, or use the more convenient bundles.
#
# BUNDLES (import one thing, and get everything in that category):
#
#   fydetabduo            base + all hardware + desktop shell
#   fydetabduo-hardware   base + all hardware, no desktop shell
#
# INDIVIDUAL MODULES (cherry-pick what you need):
#
#   base                  kernel, firmware, overlays (required by everything)
#   bluetooth             AP6275P bluetooth over ttyS9
#   suspend               deep suspend (DRAM self-refresh)
#   display-fix           fb0 cold-boot fix
#   audio                 ES8388 codec routing
#   input                 touchscreen / stylus udev rules + calibration
#   sensors               lis2dw12 accelerometer + auto-rotate
#   tablet-mode           OSK show/hide on keyboard attach/detach
#   wifi                  WiFi backend (wpa_supplicant default) + regulatory domain from timezone
#   modem                 Quectel EM05-G LTE via ModemManager
#   npu                   RK3588S NPU driver + librknnrt
#   qol                   zram, fstrim, earlyoom, etc.
#   boot-loader           U-Boot boot.scr generation
#   desktop               labwc, regreet, kanshi, keybinds
#   shell                 full desktop shell (umbrella)
#   shell-desktop         compositor & greeter only
#   shell-packages        desktop apps & fonts only
#   shell-audio           PipeWire + rtkit
#   shell-power           upower + power-profiles-daemon
#   shell-security        keyring + polkit agent
#
# Example: hardware only + your own compositor (niri):
#
#   imports = [
#     inputs.fyde-nix.nixosModules.base
#     inputs.fyde-nix.nixosModules.bluetooth
#     inputs.fyde-nix.nixosModules.suspend
#     inputs.fyde-nix.nixosModules.audio
#     inputs.fyde-nix.nixosModules.input
#     inputs.fyde-nix.nixosModules.npu
#     inputs.fyde-nix.nixosModules.qol
#     inputs.fyde-nix.nixosModules.boot-loader
#     ./my-niri-config.nix
#   ];
#
# Example: full shell but no audio or power management:
#
#   hardware.fydetabduo.shell = {
#     enable = true;
#     audio.enable = false;
#     power.enable = false;
#   };
#
# PER-USER COMPONENTS (Home Manager modules):
#
#   homeManagerModules.default     wayle + vicinae + swayidle + wl-clip-persist
#   homeManagerModules.wayle       wayle bar only
#   homeManagerModules.vicinae     vicinae launcher only
#   homeManagerModules.swayidle    idle lock only
#
# ─────────────────────────────────────────────────────────────────────────────
{ inputs, fyde-nix, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Device hardware enablement
  hardware = {
    fydetabduo = {
      enable = true;

      # Does not force landscape, but makes the default orientation landscape.
      landscape.enable = true;

      # This will dynamically override the above setting when rotation is detected.
      # Can also be toggle in the wayle bar
      sensors.autoRotate = true;

      # This does not toggle tablet mode on or off, but rather the
      # ability of tablet mode to toggle on keyboard state change, on or off.
      # Can also be toggle in the wayle bar
      tabletMode.enable = true;

      # Even without this option enabled the modem is detected automatically as it
      # is a USB 2.0 device. However, this enables integration for the in-built
      # modem module with ModemManager and NetworkManager.
      modem.enable = true;

      # Enables the RK3588S NPU using the vendor rknpu driver and librknnrt
      # runtime. Provides /dev/dri/renderD129 and the RKNN C API for
      # INT8/INT4/FP16 inference on the three NPU cores.
      npu.enable = true;
    };
  };

  # Desktop shell
  # Enable the FULL desktop experience (all parts for a whole shell).
  #
  # To select only specific parts instead, comment out the master and
  # enable only the pieces you want, e.g.:
  #   hardware.fydetabduo.shell.desktop.enable = true;
  #   hardware.fydetabduo.shell.packages.enable = true;
  #   hardware.fydetabduo.shell.audio.enable   = true;
  #   # power + security left off
  hardware.fydetabduo.shell = {
    enable = true;

    power.autoProfile = {
      # Automatically change power profile based on current charge.
      enable = true;

      # Force performance mode when plugged into AC power.
      forcePerformanceOnAC = true;
    };
  };

  # Boot
  boot.loader.fydetabduo.enable = true;

  # Networking
  networking.hostName = "fydetabduo";
  networking.networkmanager.enable = true;
  networking.modemmanager.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # Locale & timezone
  time.timeZone = "Europe/London";
  console.keyMap = "uk";
  environment.sessionVariables.XKB_DEFAULT_LAYOUT = "gb";

  # Users
  users.users.user = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "input"
    ];
    initialPassword = "fydetab";
  };

  # Pre-create the user's cache dir at boot so root-run processes don't
  # change perms on it. Kept broad on purpose.
  systemd.tmpfiles.rules = [
    "d /home/user/.cache 0755 user users -"
  ];

  # Services
  services.openssh.enable = true;

  # HM
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    sharedModules = [ fyde-nix.homeManagerModules.default ];
    extraSpecialArgs = { inherit inputs; };
    backupFileExtension = "hm-backup";
    users.user = {
      home.stateVersion = "26.05";
      home.enableNixpkgsReleaseCheck = false;

      # Optional: pick only some per-user shell parts. Everything here is on
      # by default once the module is imported; uncomment to opt specific
      # parts out, e.g., drop swayidle:
      # services.swayidle.enable = false;

      # Location for the wayle weather bar module - defaults to London, UK.
      # You should override for your own location, to fix the weather module.
      fydetabShell.wayle.weather.latitude = "51.5";
      fydetabShell.wayle.weather.longitude = "-0.1";

      xdg.userDirs = {
        enable = true;
        createDirectories = true;
      };
    };
  };

  system.stateVersion = "26.05";
}
