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
          ExecStart = "${lib.getExe pkgs.bash} -c 'set -euo pipefail; LOG=/var/log/fydetab-suspend.log; mkdir -p /var/log; echo \"=== pre-sleep $(date) ===\" > $LOG; ${lib.getExe' pkgs.networkmanager "nmcli"} -t -f UUID,TYPE,DEVICE connection show --active | ${lib.getExe pkgs.gnugrep} -E \":802-11-wireless:\" | ${lib.getExe' pkgs.coreutils "cut"} -d: -f1 > /run/fydetab-wifi-profile 2>/dev/null || true; echo saved=$(cat /run/fydetab-wifi-profile 2>/dev/null) >> $LOG; ${lib.getExe pkgs.iw} phy0 wowlan disable >> $LOG 2>&1 || true; ${lib.getExe' pkgs.util-linux "rfkill"} block wifi >> $LOG 2>&1; echo 0004:41:00.0 > /sys/bus/pci/drivers/brcmfmac/unbind 2>> $LOG || true; echo unbound-ok >> $LOG; ${lib.getExe' pkgs.coreutils "sleep"} 1; echo \"=== pre-sleep done ===\" >> $LOG'";
          ExecStop = "${lib.getExe pkgs.bash} -c 'set -uo pipefail; LOG=/var/log/fydetab-suspend.log; echo \"=== resume $(date) ===\" >> $LOG; sleep 15; echo post-resume-wait-done >> $LOG; ${lib.getExe' pkgs.util-linux "rfkill"} unblock wifi >> $LOG 2>&1 || true; echo 1 > /sys/bus/pci/devices/0004:41:00.0/remove 2>> $LOG && echo removed=ok >> $LOG || echo removed=skip >> $LOG; sleep 1; GPIO23=\"\"; if [ -d /sys/class/gpio/gpio23 ]; then GPIO23=/sys/class/gpio/gpio23; elif [ -w /sys/class/gpio/export ]; then echo 23 > /sys/class/gpio/export 2>/dev/null || true; sleep 0.2; [ -d /sys/class/gpio/gpio23 ] && GPIO23=/sys/class/gpio/gpio23; fi; echo gpio=$GPIO23 >> $LOG; if [ -n \"$GPIO23\" ]; then echo out > $GPIO23/direction 2>/dev/null || true; echo 0 > $GPIO23/value 2>/dev/null || true; sleep 1; echo 1 > $GPIO23/value 2>/dev/null || true; sleep 5; echo power-cycled >> $LOG; fi; echo 1 > /sys/bus/pci/rescan 2>> $LOG || true; sleep 5; echo rescanned >> $LOG; PCI_DEV=$(ls /sys/bus/pci/devices/ | grep 41:00.0 || true); echo pci-dev=$PCI_DEV >> $LOG; if [ -n \"$PCI_DEV\" ]; then echo 0004:41:00.0 > /sys/bus/pci/drivers/brcmfmac/bind 2>> $LOG && echo bind=ok >> $LOG || echo bind=fail-already-bound >> $LOG; else echo device-not-found >> $LOG; fi; sleep 10; systemctl start NetworkManager >> $LOG 2>&1 && echo nm-start=ok >> $LOG || echo nm-start=fail >> $LOG; NM_TRY=0; while [ $NM_TRY -lt 30 ]; do if pidof NetworkManager >/dev/null 2>&1; then echo nm-alive-at=$NM_TRY\"s\" >> $LOG; break; fi; NM_TRY=$((NM_TRY+1)); sleep 1; done; sleep 5; ${lib.getExe' pkgs.networkmanager "nmcli"} networking on >> $LOG 2>&1 || true; sleep 2; ${lib.getExe' pkgs.networkmanager "nmcli"} radio wifi on >> $LOG 2>&1 || true; echo \"=== resume done ===\" >> $LOG'";
        };
      };

      powerManagement.resumeCommands = ''
        true
      '';
    })
  ];
}
