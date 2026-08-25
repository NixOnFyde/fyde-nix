# EXEMPLAR CONFIGURATION
#
# Rebuilding with this file untouched reproduces the same system the
# image was built from. To customise, edit here or add a second
# file and import it here. Or, make your own from scratch.
#
# DESKTOP SHELL
#
# The full desktop environment (labwc, wayle, vicinae, ghostty, greeter,
# wallpaper, keybindings, idle lock, etc.) is gated behind the following
# option: hardware.fydetabduo.shell.enable = true.
#
# That option is in `modules/fydetab-duo/shell/default.nix` and
# pulls in ALL the system-level desktop packages, fonts, theming,
# pipewire audio, and the greeter.
#
# WARNING - Therefore, removing said line below gives you a
# headless system with just hardware support.
#
# The per-user config (wayle bar layout, vicinae settings, ghostty,
# swayidle) is a separate Home Manager module accessible via
# `fyde-nix.homeManagerModules.default`.
{ inputs, fyde-nix, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Device hardware enablement
  hardware.fydetabduo.enable = true;
  hardware.fydetabduo.landscape.enable = true;

  # Desktop shell
  # Enable this to get the full FydeTab experience.
  # Disable for headless / minimal setups.
  hardware.fydetabduo.shell.enable = true;

  # Boot
  boot.loader.fydetabduo.enable = true;

  # Networking
  networking.hostName = "fydetabduo";
  networking.networkmanager.enable = true;
  networking.modemmanager.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # Locale
  console.keyMap = "uk";
  environment.sessionVariables.XKB_DEFAULT_LAYOUT = "gb";

  # Users
  users.users.user = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
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
    users.user = {
      home.stateVersion = "26.05";
      home.enableNixpkgsReleaseCheck = false;
    };
  };

  system.stateVersion = "26.05";
}
