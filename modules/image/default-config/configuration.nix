# EXEMPLAR CONFIGURATION
#
# Rebuilding with this file untouched reproduces the same system the
# image was built from, except for the fact that installer-tools
# is not enabled. To customise, edit here or add a second file and
# import it here. Or, make your own from scratch.
#
# DESKTOP SHELL
#
# The full desktop environment (labwc, wayle, vicinae, alacritty, greeter,
# wallpaper, keybindings, idle lock, etc.) is made of independent parts
# defined under modules/fydetab-duo/shell/.
#
#   master:      hardware.fydetabduo.shell.enable
#   pieces:      hardware.fydetabduo.shell.{desktop,packages,audio,power,security}.enable
#
# Each piece defaults to following the master, so `shell.enable = true`
# turns on the WHOLE desktop experience (what the shipped image uses, see
# below). To include only selected pieces you can either
#   - set the master true and turn specific pieces off, or
#   - leave the master off and enable only the pieces you want, e.g.
#       hardware.fydetabduo.shell.desktop.enable = true;
#       hardware.fydetabduo.shell.packages.enable  = true;  # no audio/power/security
#
# WARNING - Turning the master (or all pieces) off gives you a headless
# system with just hardware support.
#
# The per-user config (wayle bar layout, vicinae settings, swayidle) is a
# separate Home Manager module imported below via
# `fyde-nix.homeManagerModules.default`; each of those has its own toggle
# (services.wayle.enable, programs.vicinae.enable, services.swayidle.enable)
# under the user in the home-manager block.
{ inputs, fyde-nix, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Device hardware enablement
  hardware.fydetabduo.enable = true;
  hardware.fydetabduo.landscape.enable = true;
  hardware.fydetabduo.sensors.autoRotate = true;
  hardware.fydetabduo.tabletMode.enable = true;

  # Desktop shell
  # Enable the FULL desktop experience (all parts for a whole shell).
  #
  # To select only specific parts instead, comment out the master and
  # enable only the pieces you want, e.g.:
  #   hardware.fydetabduo.shell.desktop.enable = true;
  #   hardware.fydetabduo.shell.packages.enable = true;
  #   hardware.fydetabduo.shell.audio.enable   = true;
  #   # power + security left off
  hardware.fydetabduo.shell.enable = true;
  hardware.fydetabduo.shell.power.autoProfile.enable = true;

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
      # parts out, e.g. drop swayidle:
      # services.swayidle.enable = false;

      # Location for the wayle weather bar module - defaults to London, UK.
      # You should override for your own location, to fix the weather module.
      fydetabShell.wayle.weather.latitude = 51.5;
      fydetabShell.wayle.weather.longitude = -0.1;

      xdg.userDirs = {
        enable = true;
        createDirectories = true;
      };
    };
  };

  system.stateVersion = "26.05";
}
