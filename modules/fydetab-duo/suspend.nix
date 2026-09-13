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

      # The AP6275P (dhd) registers WoWLAN wake sources, notably wake-on-
      # disconnect. On flaky/public access points that recycle clients (e.g.,
      # public wifi that times out idle stations) that fires immediately after
      # suspend, so the tablet wakes back up and ends up stuck with the screen
      # off until the power button is pressed.
      #
      # `iw phy0 wowlan disable` only clears the cfg80211 WoWLAN stuff; the
      # dhd firmware also keeps the radio in a beacon-listen mode
      # (suspend_bcn_li_dtim=10) during suspend; the DTIM/beacon interrupts
      # arrive on the OOB host-wake GPIO (dhdpcie_host_wake) and yanks the SoC
      # back out of deep sleep within seconds ("Wakeup due to WLAN"). Disabling
      # the radio entirely with rfkill at suspend stops those beacons, then we
      # re-enable it on resume so NetworkManager reconnects.
      systemd.services."wowlan-disable" = {
        description = "Disable WiFi wake sources before suspend, restore on resume";
        before = [ "sleep.target" ];
        wantedBy = [ "sleep.target" ];
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${lib.getExe pkgs.bash} -c '${lib.getExe' pkgs.networkmanager "nmcli"} -t -f UUID,TYPE,DEVICE connection show --active | ${lib.getExe pkgs.gnugrep} -E \":802-11-wireless:\" | ${lib.getExe' pkgs.coreutils "cut"} -d: -f1 > /run/fydetab-wifi-profile; ${lib.getExe pkgs.iw} phy0 wowlan disable || true; ${lib.getExe' pkgs.util-linux "rfkill"} block wifi; PCI_DEV=\"\$(cd /sys/bus/pci/devices && ls -d *:41:00.0 2>/dev/null || true)\"; PCI_DEV=\"\${PCI_DEV:-0004:41:00.0}\"; echo \"\$PCI_DEV\" > /sys/bus/pci/drivers/brcmfmac/unbind || true; ${lib.getExe' pkgs.coreutils "sleep"} 1'";
          ExecStop = "${lib.getExe' pkgs.util-linux "rfkill"} unblock wifi";
        };
      };

      # NixOS runs resumeCommands after systemd-sleep has returned from the
      # kernel suspend operation, making it actually work unlike the ExecStop
      # that is also used above just in case. Only reconnect the profile that
      # was active before suspend; trying every saved profile causes attempts
      # against networks that are not in range which we obviously don't want.
      powerManagement.resumeCommands = ''
        ${lib.getExe' pkgs.util-linux "rfkill"} unblock wifi || true
        ${lib.getExe' pkgs.networkmanager "nmcli"} radio wifi on || true

        # The BCM43752 firmware ignores the D3 mailbox; keeping the driver
        # bound during suspend leaves the chip desynced and any re-probe /
        # rebind after resume panics (half-reset chip outs a false shared-RAM
        # size and the fw load writes past the BAR1 iomap). Instead of trying
        # to recover a desynced chip, "wowlan-disable" unbinds the driver
        # BEFORE suspend, so the PCI core handles a plain config-level D3hot
        # cycle (known to suspend and resume without issues), and here we just
        # rebind afterwards for a clean firmware load - akin to ze first boot.
        PCI_DEV="$(cd /sys/bus/pci/devices && ls -d *:41:00.0 2>/dev/null || true)"
        PCI_DEV="''${PCI_DEV:-0004:41:00.0}"
        echo "$PCI_DEV" > /sys/bus/pci/drivers/brcmfmac/bind || true

        wifi_profile="$(${lib.getExe' pkgs.coreutils "cat"} /run/fydetab-wifi-profile 2>/dev/null || true)"
        if [ -n "$wifi_profile" ]; then
          # The driver rebind above recreates the netdev; wait for it and for
          # NetworkManager to pick it up. Retry while the saved profile
          # starts working.
          for _ in $(${lib.getExe' pkgs.coreutils "seq"} 1 30); do
            ${lib.getExe' pkgs.networkmanager "nmcli"} device wifi rescan || true

            if ${lib.getExe' pkgs.networkmanager "nmcli"} connection up uuid "$wifi_profile"; then
              exit 0
            fi

            ${lib.getExe' pkgs.coreutils "sleep"} 1
          done
        fi
      '';
    })
  ];
}
