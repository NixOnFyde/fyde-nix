# Hardware-only module for the FydeTab Duo.
#
# Imports all hardware features (kernel, GPU, WiFi, BT, audio, touchscreen,
# accelerometer, tablet-mode, modem, boot-loader, suspend, QoL) but does NOT
# include the desktop shell (labwc, wayle, vicinae, greeter theming, etc.).
#
# Use this when you want to add your own compositor / desktop environment
# (e.g., niri, sway, GNOME) instead of the default labwc-based shell.
#
# For more granular control, import individual modules from the flake instead:
#
#   nixosModules.base              -- kernel, firmware, overlays
#   nixosModules.bluetooth         -- AP6275P bluetooth
#   nixosModules.suspend           -- deep suspend
#   nixosModules.display-fix       -- fb0 cold-boot fix
#   nixosModules.audio             -- ES8388 codec routing
#   nixosModules.input             -- touchscreen / stylus udev
#   nixosModules.sensors           -- accelerometer + auto-rotate
#   nixosModules.tablet-mode       -- OSK show/hide
#   nixosModules.wifi              -- WiFi backend (iwd default) + regulatory domain
#   nixosModules.modem             -- Quectel EM05-G LTE
#   nixosModules.npu               -- RK3588S NPU driver
#   nixosModules.qol               -- QoL defaults
#   nixosModules.boot-loader       -- U-Boot boot.scr
#
# The host must apply the fyde-nix overlay to get the custom kernel and
# firmware packages. This module applies it automatically using base.nix,
# but if you are using the modules manually, make sure:
#
#   nixpkgs.overlays = [ inputs.fyde-nix.overlays.default ];
#
# Usage in a flake:
#
#   inputs.fyde-nix.nixosModules.fydetabduo-hardware
#
# Then set hardware.fydetabduo.enable = true; and add your own
# compositor, greeter, etc. separately.
{ ... }:
{
  imports = [
    # Core, kernel, firmware, overlays (shared with default.nix)
    ./base.nix

    # Hardware sub-modules (compositor-agnostic)
    ./boot-loader.nix
    ./suspend.nix
    ./bluetooth.nix
    ./display-fix.nix
    ./es8388-audio.nix
    ./input.nix
    ./npu.nix
    ./sensors.nix
    ./tablet-mode.nix
    ./wifi-regdom.nix
    ./modem.nix
    ./qol.nix
  ];
}
