{
  config,
  lib,
  pkgs,
  ...
}:
let
  shell = config.hardware.fydetabduo.shell;
in
{
  options.hardware.fydetabduo.shell.power.enable = lib.mkOption {
    type = lib.types.bool;
    default = shell.enable;
    description = ''
      Power management (upower + power-profiles-daemon for battery
      reporting). Defaults to following hardware.fydetabduo.shell.enable;
      set it independently to include or exclude just this part.
    '';
  };

  config = lib.mkIf shell.power.enable {
    # Power management (battery reporting for wayle)
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;

    # Physical power button (rk805 pwrkey): short press suspends (sleep),
    # long press still powers off. NixOS by default powers off on a short
    # press, which is wrong for a tablet.
    services.logind.settings.Login = {
      HandlePowerKey = "suspend";
      HandlePowerKeyLongPress = "poweroff";
    };

    # power-profiles-daemon cannot give us a performance profile here:
    # that requires an ACPI platform-profile interface, which this SoC
    # does not expose. The CPU/GPU GOVERNORS do support it though,
    # so fydetab-perf switches them directly:
    #   fydetab-perf on    -> performance governor on all CPUs + GPU
    #   fydetab-perf off   -> back to schedutil / simple_ondemand
    #   fydetab-perf status-> "on" or "off"
    # A reboott will restore the default governors.
    # Passwordless via sudo (NOPASSWD rule below) is used so the wayle
    # bar toggle can switch it with any other user interaction.
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "fydetab-perf" ''
        set -euo pipefail

        case "''${1:-}" in
        on)
          for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo performance >"$g" 2>/dev/null || true
          done
          for g in /sys/class/devfreq/*/governor; do
            echo performance >"$g" 2>/dev/null || true
          done
          echo "performance mode ON"
          ;;
        off)
          for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo schedutil >"$g" 2>/dev/null || true
          done
          for g in /sys/class/devfreq/*/governor; do
            echo simple_ondemand >"$g" 2>/dev/null || true
          done
          echo "performance mode OFF"
          ;;
        status)
          if [ "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)" = performance ]; then
            echo on
          else
            echo off
          fi
          ;;
        *)
          echo "usage: fydetab-perf {on|off|status}" >&2
          exit 2
          ;;
        esac
      '')
    ];

    security.sudo.extraRules = [
      {
        groups = [ "wheel" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/fydetab-perf";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
