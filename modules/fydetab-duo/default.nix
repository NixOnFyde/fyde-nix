# This is the full FydeTab Duo module: with hardware + desktop shell.
#
# This is a convenience bundle that imports everything. For more granular
# control, import individual modules from the flake instead:
#
#   nixosModules.base              -- kernel, firmware, overlays
#   nixosModules.bluetooth         -- AP6275P bluetooth
#   nixosModules.suspend           -- deep suspend (DRAM self-refresh)
#   nixosModules.display-fix       -- fb0 cold-boot fix
#   nixosModules.audio             -- ES8388 codec routing
#   nixosModules.input             -- touchscreen / stylus udev
#   nixosModules.sensors           -- accelerometer + auto-rotate
#   nixosModules.tablet-mode       -- OSK show/hide on keyboard attach
#   nixosModules.wifi              -- WiFi regulatory domain
#   nixosModules.modem             -- Quectel EM05-G LTE
#   nixosModules.npu               -- RK3588S NPU driver
#   nixosModules.qol               -- QoL defaults (zram, fstrim, etc.)
#   nixosModules.boot-loader       -- U-Boot boot.scr
#   nixosModules.desktop           -- labwc, regreet, kanshi, keybinds
#   nixosModules.shell             -- full desktop shell umbrella
#   nixosModules.shell-desktop     -- compositor & greeter only
#   nixosModules.shell-packages    -- desktop apps & fonts only
#   nixosModules.shell-audio       -- PipeWire only
#   nixosModules.shell-power       -- upower + power-profiles-daemon
#   nixosModules.shell-security    -- keyring + polkit agent
#
# Or use the hardware-only bundle (no desktop shell):
#
#   nixosModules.fydetabduo-hardware
#
# Each feature is guarded by its own enable option, so even with the
# full bundle on you can turn pieces off:
#
#   hardware.fydetabduo.modem.enable = false;
#   hardware.fydetabduo.shell.audio.enable = false;
#
# Per-user components (wayle, vicinae, swayidle) are Home Manager
# modules exposed separately:
#
#   homeManagerModules.default     -- all per-user components
#   homeManagerModules.wayle       -- wayle bar only
#   homeManagerModules.vicinae     -- vicinae launcher only
#   homeManagerModules.swayidle    -- idle lock only
{ ... }:
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
