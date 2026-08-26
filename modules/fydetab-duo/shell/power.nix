{
  config,
  lib,
  pkgs,
  ...
}:
let
  shell = config.hardware.fydetabduo.shell;
  autoCfg = shell.power.autoProfile;
in
{
  options.hardware.fydetabduo.shell.power = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = shell.enable;
      description = ''
        Power management (upower + power-profiles-daemon for battery
        reporting). Defaults to following hardware.fydetabduo.shell.enable;
        set it independently to include or exclude just this part.
      '';
    };

    autoProfile = {
      enable = lib.mkEnableOption ''
        Automatically switch power profiles based on battery percentage.
        - Above highThreshold: performance (CPU/GPU performance governor)
        - Between low and high: balanced (schedutil / simple_ondemand)
        - Below lowThreshold: power-saver (power-profiles-daemon power-saver)
      '';
      highThreshold = lib.mkOption {
        type = lib.types.int;
        default = 50;
        description = "Battery percentage above which performance mode activates.";
      };
      lowThreshold = lib.mkOption {
        type = lib.types.int;
        default = 20;
        description = "Battery percentage below which power-saver mode activates.";
      };
    };
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
    # A reboot will restore the default governors.
    # Passwordless via sudo (NOPASSWD rule below) is used so the wayle
    # bar toggle can switch it without any user interaction.
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
      {
        groups = [ "wheel" ];
        commands = [
          {
            command = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    # Auto power profile switching
    systemd.user.services.fydetab-auto-profile = lib.mkIf autoCfg.enable {
      description = "Auto power profile switching based on battery percentage";
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = pkgs.writeShellScript "fydetab-auto-profile" ''
          set -euo pipefail

          UPOWER="${pkgs.upower}/bin/upower"
          SUDO="${pkgs.sudo}/bin/sudo"
          PERF="/run/current-system/sw/bin/fydetab-perf"
          PPD="${pkgs.power-profiles-daemon}/bin/powerprofilesctl"
          STATE_FILE="/run/tablet-mode/auto-profile-state"
          HIGH=${toString autoCfg.highThreshold}
          LOW=${toString autoCfg.lowThreshold}

          get_battery_pct() {
            "$UPOWER" -i /org/freedesktop/UPower/devices/battery_sbs_5_000b 2>/dev/null \
              | awk '/percentage/{gsub(/%/,"",$2); print int($2)}'
          }

          apply_profile() {
            local current
            current=$(cat "$STATE_FILE" 2>/dev/null || echo "")
            local pct
            pct=$(get_battery_pct)
            [ -z "$pct" ] && return

            local target
            if [ "$pct" -ge "$HIGH" ]; then
              target="performance"
            elif [ "$pct" -le "$LOW" ]; then
              target="power-saver"
            else
              target="balanced"
            fi

            [ "$target" = "$current" ] && return
            mkdir -p "$(dirname "$STATE_FILE")"
            echo "$target" > "$STATE_FILE"

            case "$target" in
              performance) "$SUDO" -n "$PERF" on  || true ;;
              balanced)    "$SUDO" -n "$PERF" off || true ;;
              power-saver) "$SUDO" -n "$PPD" power-saver || true ;;
            esac
          }

          # Apply on startup
          apply_profile

          # React to battery changes
          "$UPOWER" --monitor | while IFS= read -r _; do
            apply_profile
          done
        '';
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
