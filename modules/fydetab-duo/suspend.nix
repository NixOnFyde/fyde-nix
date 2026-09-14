{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo;
in
{
  options.hardware.fydetabduo = {
    deepSuspend.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Default to deep suspend (DRAM self-refresh) and pin systemd to
        `mem` only, avoiding the multi-state re-suspend loop after flaky
        wakes.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.deepSuspend.enable {
      boot.kernelParams = [ "mem_sleep_default=deep" ];

      systemd.sleep.settings.Sleep.SuspendState = "mem";

      systemd.services."wowlan-disable" = {
        description = "Disable WiFi wake sources before suspend, restore on resume";
        before = [ "sleep.target" ];
        wantedBy = [ "sleep.target" ];
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${lib.getExe pkgs.bash} -c 'set -euo pipefail; LOG=/var/log/fydetab-suspend.log; mkdir -p /var/log; echo \"=== pre-sleep $(date) ===\" > $LOG; ${lib.getExe' pkgs.networkmanager "nmcli"} -t -f UUID,TYPE,DEVICE connection show --active | ${lib.getExe pkgs.gnugrep} -E \":802-11-wireless:\" | ${lib.getExe' pkgs.coreutils "cut"} -d: -f1 > /run/fydetab-wifi-profile 2>/dev/null || true; echo saved=$(cat /run/fydetab-wifi-profile 2>/dev/null) >> $LOG; ${lib.getExe pkgs.iw} phy0 wowlan disable >> $LOG 2>&1 || true; ${lib.getExe' pkgs.util-linux "rfkill"} block wifi >> $LOG 2>&1; echo none > /sys/bus/pci/devices/0004:41:00.0/driver_override 2>/dev/null || true; echo override=$(cat /sys/bus/pci/devices/0004:41:00.0/driver_override 2>/dev/null) >> $LOG; echo 0004:41:00.0 > /sys/bus/pci/drivers/brcmfmac/unbind 2>> $LOG || true; echo unbound-ok >> $LOG; ${lib.getExe' pkgs.coreutils "sleep"} 1; echo \"=== pre-sleep done ===\" >> $LOG'";
          ExecStop = "${lib.getExe pkgs.bash} -c 'set -uo pipefail; LOG=/var/log/fydetab-suspend.log; echo \"=== resume $(date) ===\" >> $LOG; ${lib.getExe' pkgs.util-linux "rfkill"} unblock wifi >> $LOG 2>&1 || true; ${lib.getExe' pkgs.networkmanager "nmcli"} radio wifi on >> $LOG 2>&1 || true; GPIO23=\"\"; if [ -d /sys/class/gpio/gpio23 ]; then GPIO23=/sys/class/gpio/gpio23; elif [ -w /sys/class/gpio/export ]; then echo 23 > /sys/class/gpio/export 2>/dev/null || true; sleep 0.2; [ -d /sys/class/gpio/gpio23 ] && GPIO23=/sys/class/gpio/gpio23; fi; echo gpio=$GPIO23 >> $LOG; if [ -n \"$GPIO23\" ]; then echo out > $GPIO23/direction 2>/dev/null || true; echo 0 > $GPIO23/value 2>/dev/null || true; sleep 1; echo 1 > $GPIO23/value 2>/dev/null || true; sleep 3; fi; echo 1 > /sys/bus/pci/rescan 2>> $LOG || true; sleep 2; echo rescanned >> $LOG; echo 0004:41:00.0 > /sys/bus/pci/drivers/brcmfmac/bind 2>> $LOG && echo bind=ok >> $LOG || echo bind=fail >> $LOG; sleep 3; ${lib.getExe' pkgs.networkmanager "nmcli"} radio wifi on >> $LOG 2>&1 || true; WP=$(cat /run/fydetab-wifi-profile 2>/dev/null || true); if [ -n \"$WP\" ]; then echo reconnect=$WP >> $LOG; ${lib.getExe' pkgs.networkmanager "nmcli"} connection up $WP >> $LOG 2>&1 || true; fi; echo wifi=$(nmcli -t -f DEVICE,STATE,CONNECTION d 2>/dev/null | grep -iE ^wl || echo none) >> $LOG; echo \"=== resume done ===\" >> $LOG'";
        };
      };

      powerManagement.resumeCommands = ''
        ${lib.getExe' pkgs.util-linux "rfkill"} unblock wifi || true
        ${lib.getExe' pkgs.networkmanager "nmcli"} radio wifi on || true

        GPIO_23=""
        if [ -d /sys/class/gpio/gpio23 ]; then
          GPIO_23=/sys/class/gpio/gpio23
        elif [ -w /sys/class/gpio/export ]; then
          echo 23 > /sys/class/gpio/export 2>/dev/null || true
          sleep 0.2
          [ -d /sys/class/gpio/gpio23 ] && GPIO_23=/sys/class/gpio/gpio23
        fi
        if [ -n "$GPIO_23" ]; then
          echo out > "$GPIO_23/direction" 2>/dev/null || true
          rail_safe() {
            echo 1 > "$GPIO_23/value" 2>/dev/null || true
            sleep 0.25 2>/dev/null || sleep 1
            return 0
          }
          trap rail_safe EXIT HUP INT TERM
          echo 0 > "$GPIO_23/value" 2>/dev/null || true
          sleep 0.25 2>/dev/null || sleep 1
          echo 1 > "$GPIO_23/value" 2>/dev/null || true
          sleep 2 2>/dev/null || sleep 2
          trap - EXIT HUP INT TERM
        fi
        echo 1 > /sys/bus/pci/rescan 2>/dev/null || true
        sleep 2
        PCI_DEV="$(cd /sys/bus/pci/devices && ls -d *:41:00.0 2>/dev/null | head -1 || true)"
        PCI_DEV="''${PCI_DEV:-0004:41:00.0}"
        echo "$PCI_DEV" > /sys/bus/pci/drivers/brcmfmac/bind 2>/dev/null || true
        sleep 2
        ${lib.getExe' pkgs.networkmanager "nmcli"} radio wifi on || true
        wifi_profile="$(${lib.getExe' pkgs.coreutils "cat"} /run/fydetab-wifi-profile 2>/dev/null || true)"
        if [ -n "$wifi_profile" ]; then
          ${lib.getExe' pkgs.networkmanager "nmcli"} connection up "$wifi_profile" || true
        fi
      '';
    })
  ];
}
