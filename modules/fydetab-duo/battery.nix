{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo.battery;
  defaultRechargeAt = builtins.min (builtins.max 10 (cfg.chargeLimit - 5)) (cfg.chargeLimit - 1);
  rechargeAt = if cfg.rechargeAt != null then cfg.rechargeAt else defaultRechargeAt;
in
{
  options.hardware.fydetabduo.battery = {
    chargeLimit = lib.mkOption {
      type = lib.types.nullOr (lib.types.ints.between 1 100);
      default = null;
      description = ''
        Battery charge ceiling (percent). When set, charging is
        inhibited at this level using the SC8886 charger's CHRG_INHIBIT
        register. Set to null to charge fully (default).
      '';
    };
    rechargeAt = lib.mkOption {
      type = lib.types.nullOr (lib.types.ints.between 0 99);
      default = null;
      description = ''
        Battery charge floor (percent). Charging resumes when
        capacity drops below this level. When null, defaults to
        chargeLimit - 5 (but at least 10).
      '';
    };
  };

  config = lib.mkIf (cfg.chargeLimit != null) {
    assertions = [
      {
        assertion =
          cfg.chargeLimit > rechargeAt;
        message = "hardware.fydetabduo.battery.rechargeAt must be less than chargeLimit";
      }
    ];

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "fydetab-chargelimit" ''
        set -euo pipefail

        CHARGER="/sys/class/power_supply/bq25700-charger"

        read_val() {
          cat "$CHARGER/$1" 2>/dev/null || echo ""
        }

        write_val() {
          echo "$2" > "$CHARGER/$1" 2>/dev/null
        }

        validate_percent() {
          case "$1" in
            "" | *[!0-9]*) return 1 ;;
          esac
          [ "''${#1}" -le 3 ]
        }

        case "''${1:-status}" in
        status)
          [ "$#" -le 1 ] || { echo "usage: fydetab-chargelimit status" >&2; exit 2; }
          limit=$(read_val charge_control_limit)
          start=$(read_val charge_control_start_threshold)
          if [ -z "$limit" ] || [ "$limit" = "100" ]; then
            echo "off"
          else
            echo "limit=$limit recharge=$start"
          fi
          ;;
        set)
          [ "$#" -ge 2 ] && [ "$#" -le 3 ] || { echo "usage: fydetab-chargelimit set <end> [start]" >&2; exit 2; }
          end_val="$2"
          validate_percent "$end_val" || { echo "error: end must be an integer from 1 to 100" >&2; exit 2; }
          end_num=$((10#$end_val))
          [ "$end_num" -ge 1 ] && [ "$end_num" -le 100 ] || { echo "error: end must be from 1 to 100" >&2; exit 2; }

          if [ "$#" -eq 3 ]; then
            start_val="$3"
          else
            start_num=$((end_num - 5))
            [ "$start_num" -lt 10 ] && start_num=10
            [ "$start_num" -ge "$end_num" ] && start_num=$((end_num - 1))
            start_val="$start_num"
          fi
          validate_percent "$start_val" || { echo "error: start must be an integer from 0 to 99" >&2; exit 2; }
          start_num=$((10#$start_val))
          [ "$start_num" -lt "$end_num" ] || { echo "error: start must be less than end" >&2; exit 2; }
          [ "$start_num" -le 99 ] || { echo "error: start must be from 0 to 99" >&2; exit 2; }

          start_val="$start_num"
          write_val charge_control_start_threshold "$start_val"
          write_val charge_control_limit "$end_num"
          echo "charge limit: $end_num%, recharge below $start_num%"
          ;;
        off)
          [ "$#" -eq 1 ] || { echo "usage: fydetab-chargelimit off" >&2; exit 2; }
          write_val charge_control_limit 100
          echo "charge limit: off (charging to full)"
          ;;
        *)
          echo "usage: fydetab-chargelimit {set <end> [start]|off|status}" >&2
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
            command = "/run/current-system/sw/bin/fydetab-chargelimit";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    systemd.services.fydetab-charge-limit = {
      description = "Apply battery charge limit";
      wantedBy = [ "multi-user.target" ];
      after = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = "/sys/class/power_supply/bq25700-charger";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "fydetab-charge-limit-apply" ''
          CHARGER="/sys/class/power_supply/bq25700-charger"
          LIMIT=${toString cfg.chargeLimit}
          START=${toString rechargeAt}

          echo "$START" > "$CHARGER/charge_control_start_threshold"
          echo "$LIMIT"  > "$CHARGER/charge_control_limit"
          echo "battery: charge limit ${toString cfg.chargeLimit}%, recharge below $START%"
        '';
      };
    };
  };
}
