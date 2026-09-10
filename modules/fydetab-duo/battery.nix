{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo.battery;
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
          cfg.chargeLimit > (if cfg.rechargeAt != null then cfg.rechargeAt else (cfg.chargeLimit - 5));
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

        case "''${1:-status}" in
        status)
          limit=$(read_val charge_control_limit)
          start=$(read_val charge_control_start_threshold)
          if [ -z "$limit" ] || [ "$limit" = "100" ]; then
            echo "off"
          else
            echo "limit=$limit recharge=$start"
          fi
          ;;
        set)
          end_val="''${2:-80}"
          start_val="''${3:-$((end_val - 5))}"
          [ "$start_val" -lt 10 ] && start_val=10
          write_val charge_control_start_threshold "$start_val"
          write_val charge_control_limit "$end_val"
          echo "charge limit: $end_val%, recharge below $start_val%"
          ;;
        off)
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
          START=${toString (if cfg.rechargeAt != null then cfg.rechargeAt else (cfg.chargeLimit - 5))}

          [ "$START" -lt 10 ] && START=10

          echo "$START" > "$CHARGER/charge_control_start_threshold"
          echo "$LIMIT"  > "$CHARGER/charge_control_limit"
          echo "battery: charge limit ${toString cfg.chargeLimit}%, recharge below $START%"
        '';
      };
    };
  };
}
