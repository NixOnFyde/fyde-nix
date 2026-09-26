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

      # PRE-SUSPEND: detach Wi-Fi before SoC DRAM self-refresh
      systemd.services."fydetab-wifi-suspend" = {
        description = "Prepare AP6275P Wi-Fi for deep sleep / hibernate";
        before = [
          "sleep.target"
          "systemd-suspend.service"
          "systemd-hibernate.service"
          "systemd-hybrid-sleep.service"
          "systemd-suspend-then-hibernate.service"
        ];
        wantedBy = [ "sleep.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "fydetab-wifi-suspend" ''
            set -uo pipefail
            LOG="/var/log/fydetab-suspend.log"
            mkdir -p /var/log
            echo "## pre-sleep $(date -Is)" > "$LOG"

            # Save active Wi-Fi profile UUID
            active_uuid=$(${lib.getExe' pkgs.networkmanager "nmcli"} -t -f UUID,TYPE connection show --active 2>/dev/null \
              | ${lib.getExe pkgs.gnugrep} -E ":802-11-wireless" \
              | ${lib.getExe' pkgs.coreutils "cut"} -d: -f1 \
              | head -n1 || true)
            echo "$active_uuid" > /run/fydetab-wifi-profile
            echo "saved_profile=$active_uuid" >> "$LOG"

            # Disable WoWLAN and unbind PCI device
            ${lib.getExe pkgs.iw} phy0 wowlan disable >> "$LOG" 2>&1 || true
            ${lib.getExe' pkgs.util-linux "rfkill"} block wifi >> "$LOG" 2>&1 || true

            if [ -d "/sys/bus/pci/drivers/brcmfmac/0004:41:00.0" ]; then
              echo "0004:41:00.0" > /sys/bus/pci/drivers/brcmfmac/unbind 2>> "$LOG" || true
              echo "unbound=ok" >> "$LOG"
            fi

            if [ -d "/sys/bus/pci/devices/0004:41:00.0" ]; then
              echo 1 > /sys/bus/pci/devices/0004:41:00.0/remove 2>> "$LOG" || true
              echo "removed=ok" >> "$LOG"
            fi

            echo "## pre-sleep done" >> "$LOG"
          '';
        };
      };

      # POST-RESUME: rail-cycle, rescan, wait for netdev, restart NM
      systemd.services."fydetab-wifi-resume" = {
        description = "Recover AP6275P Wi-Fi hardware and restart NetworkManager";
        after = [
          "systemd-suspend.service"
          "systemd-hibernate.service"
          "systemd-hybrid-sleep.service"
          "systemd-suspend-then-hibernate.service"
        ];
        wantedBy = [
          "systemd-suspend.service"
          "systemd-hibernate.service"
          "systemd-hybrid-sleep.service"
          "systemd-suspend-then-hibernate.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "fydetab-wifi-resume" ''
            set -uo pipefail
            LOG="/var/log/fydetab-suspend.log"
            echo "## resume $(date -Is)" >> "$LOG"

            ${lib.getExe' pkgs.util-linux "rfkill"} unblock wifi >> "$LOG" 2>&1 || true

            # Remove zombie device if still lingering
            if [ -d "/sys/bus/pci/devices/0004:41:00.0" ]; then
              echo 1 > /sys/bus/pci/devices/0004:41:00.0/remove 2>> "$LOG" || true
              echo "removed=ok" >> "$LOG"
            fi

            # Export and toggle GPIO23 (AP6275P power rail)
            GPIO_DIR=""
            if [ -d "/sys/class/gpio/gpio23" ]; then
              GPIO_DIR="/sys/class/gpio/gpio23"
            elif [ -w "/sys/class/gpio/export" ]; then
              echo 23 > /sys/class/gpio/export 2>/dev/null || true
              sleep 0.2
              [ -d "/sys/class/gpio/gpio23" ] && GPIO_DIR="/sys/class/gpio/gpio23"
            fi

            if [ -n "$GPIO_DIR" ]; then
              echo out > "$GPIO_DIR/direction" 2>/dev/null || true
              echo 0 > "$GPIO_DIR/value" 2>/dev/null || true
              sleep 0.5
              echo 1 > "$GPIO_DIR/value" 2>/dev/null || true
              sleep 2
              echo "rail_power_cycled=ok" >> "$LOG"
            else
              echo "gpio23_error=not_found" >> "$LOG"
            fi

            # Rescan PCIe bus
            echo 1 > /sys/bus/pci/rescan 2>> "$LOG" || true
            sleep 1

            # Wait for brcmfmac to initialize and populate the network interface
            iface=""
            for i in $(seq 1 30); do
              for dev in /sys/class/net/*; do
                [ -e "$dev" ] || continue
                name=$(basename "$dev")
                if [ "$name" != "lo" ] && [ -d "$dev/wireless" -o -d "$dev/phy80211" ]; then
                  iface="$name"
                  break 2
                fi
              done
              sleep 0.5
            done

            echo "netdev_found=$iface (after $i checks)" >> "$LOG"

            # Restart NetworkManager as it should be now that the hardware and netdev exist
            echo "restarting_networkmanager..." >> "$LOG"
            ${lib.getExe' pkgs.systemd "systemctl"} restart NetworkManager 2>> "$LOG" || true

            # Wait for NM daemon to respond to commands
            nm_ok=0
            for i in $(seq 1 20); do
              if ${lib.getExe' pkgs.networkmanager "nmcli"} general status >/dev/null 2>&1; then
                nm_ok=1
                break
              fi
              sleep 0.5
            done
            echo "nm_ready=$nm_ok" >> "$LOG"

            # Reconnect saved Wi-Fi profile if present
            if [ -f "/run/fydetab-wifi-profile" ]; then
              saved_uuid=$(cat /run/fydetab-wifi-profile || true)
              if [ -n "$saved_uuid" ] && [ "$nm_ok" -eq 1 ]; then
                sleep 1
                ${lib.getExe' pkgs.networkmanager "nmcli"} connection up uuid "$saved_uuid" >> "$LOG" 2>&1 || true
                echo "reconnected_uuid=$saved_uuid" >> "$LOG"
              fi
            fi

            echo "## resume done" >> "$LOG"
          '';
        };
      };
    })
  ];
}
