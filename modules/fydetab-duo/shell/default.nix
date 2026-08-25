{
  lib,
  ...
}:
{
  imports = [
    ./desktop.nix
    ./packages.nix
    ./audio.nix
    ./power.nix
    ./security.nix
  ];

  options.hardware.fydetabduo.shell.enable = lib.mkEnableOption ''
    The default FydeTab Duo desktop shell with: labwc theming, root menu,
    wallpaper / keybind setup, keyring, polkit agent, and idle lock.
    Enables every part of the shell (compositor/greeter, packages, audio,
    power, security).

    To include only selected parts, set individual sub-options under
    hardware.fydetabduo.shell.{desktop,packages,audio,power,security} which
    default to following this option.

    Per-user components are provided as a Home Manager module; import
    `fyde-nix.homeManagerModules.default` into home-manager.sharedModules.
  '';
}
