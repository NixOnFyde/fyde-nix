{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.hardware.fydetabduo.wifi) countryCode;

  regdomScript = pkgs.writeShellScript "fydetab-wifi-regdom" (
    if countryCode != null then
      ''
        exec ${lib.getExe' pkgs.iw "iw"} reg set ${countryCode}
      ''
    else
      ''
        timezone=$(readlink -f /etc/localtime || true)
        timezone=''${timezone#/usr/share/zoneinfo/}
        country=''${timezone%%/*}

        case "$country" in
          ??) ;;
          *)
            country=""
            [ -n "$timezone" ] && country=$(${pkgs.gawk}/bin/awk -v tz="$timezone" '$3 == tz {print $1; exit}' ${pkgs.tzdata}/share/zoneinfo/zone.tab)
            ;;
        esac

        case "$country" in
          [A-Z][A-Z]) exec ${lib.getExe' pkgs.iw "iw"} reg set "$country" ;;
          *)
            echo "no country for timezone '$timezone', leaving regdom unchanged" >&2
            exit 0
            ;;
        esac
      ''
  );
in
{
  options.hardware.fydetabduo = {
    wifi.countryCode = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[A-Z]{2}");
      default = null;
      example = "DE";
      description = "Fixed WiFi regulatory country. When null, derived from the system timezone.";
    };

    autoRegulatoryDomain.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Apply a WiFi regulatory domain at boot (from countryCode or timezone).";
    };
  };

  config = lib.mkIf config.hardware.fydetabduo.autoRegulatoryDomain.enable {
    systemd.services.fydetab-wifi-regdom = {
      description = "Apply WiFi regulatory domain";
      after = [ "systemd-modules-load.service" ];
      before = [
        "network-pre.target"
        "iwd.service"
        "wpa_supplicant.service"
      ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = "/sys/class/ieee80211";

      serviceConfig = {
        Type = "oneshot";
        ExecStart = regdomScript;
        RemainAfterExit = true;
      };
    };
  };
}
