# This is the full FydeTab Duo module: with hardware + desktop shell.
#
# For hardware-only, use ./hardware.nix instead.
{
  ...
}:
{
  imports = [
    # Core, kernel, firmware, overlays (shared with hardware.nix)
    ./base.nix

    # Hardware sub-modules (compositor-agnostic)
    ./boot-loader.nix
    ./suspend.nix
    ./bluetooth.nix
    ./display-fix.nix
    ./es8388-audio.nix
    ./input.nix
    ./sensors.nix
    ./tablet-mode.nix
    ./wifi-regdom.nix
    ./modem.nix
    ./npu.nix
    ./qol.nix

    # Desktop shell (labwc, greeter, wayle, vicinae, etc.)
    ./desktop.nix
    ./shell
  ];
}
