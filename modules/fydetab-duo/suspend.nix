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
      #
      # The AP6275P cannot survive a *driver-level* rebind on a chip that is
      # merely clock/PCI-desynced after deep suspend — the chip comes back in a
      # state where the PCI core no longer sees a link it can restore, and any
      # bind from that half-alive state panics the host. The only bind that is
      # reproducibly safe is a *cold* bind, the "first boot" bind: the chip is
      # fully powered by its own rail (WIFI poweren = gpio23 / RK_PC7), so it
      # boots its ROM/secondary bootloader/firmware from a true cold state,
      # which is what the vendor dhd driver relied on. So on resume we do NOT
      # rebind into a desynced chip — we cold power-cycle the rail
      # (rail OFF -> chip fully powered down, rail ON -> chip boots clean) and
      # THEN bind brcmfmac. Proven live on this tablet: rail power-cycle +
      # bind survives and gives back working wifi with the SAME boot_id.
      powerManagement.resumeCommands = ''
        ${lib.getExe' pkgs.util-linux "rfkill"} unblock wifi || true
        ${lib.getExe' pkgs.networkmanager "nmcli"} radio wifi on || true

        # Cold power-cycle the WLAN chip: rail OFF (chip truly loses power,
        # its state is gone) so the PCIe endpoint is a fresh "first boot"
        # device again, then rail ON and bind brcmfmac onto the clean chip.
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
          echo 0 > "$GPIO_23/value" 2>/dev/null || true   # rail OFF - chip fully cold
          sleep lav
          echo 1 > "$GPIO_23/value" 2>/dev/null || true   # rail ON - chip boots clean
          sleep 2
        fi
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
