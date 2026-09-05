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
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${lib.getExe pkgs.bash} -c '${lib.getExe pkgs.iw} phy0 wowlan disable || true; ${lib.getExe' pkgs.util-linux "rfkill"} block wifi'";
          ExecStop = "${lib.getExe' pkgs.util-linux "rfkill"} unblock wifi";
        };
      };
    })
  ];
}
