{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.fydetabduo;
in {
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
      boot.kernelParams = ["mem_sleep_default=deep"];

      systemd.sleep.settings.Sleep.SuspendState = "mem";

      # The AP6275P (dhd) registers WoWLAN wake sources, notably wake-on-
      # disconnect. On flaky/public access points that recycle clients (e.g.,
      # public wifi that times out idle stations) that fires immediately after
      # suspend, so the tablet wakes back up and ends up stuck with the screen
      # off until the power button is pressed. Disable WoWLAN before suspend so
      # WiFi can't yank the device out of sleep.
      systemd.services."wowlan-disable" = {
        description = "Disable WiFi WoWLAN wake sources before suspend";
        before = ["systemd-suspend.service"];
        wantedBy = ["sleep.target"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.iw}/bin/iw phy0 wowlan disable";
        };
      };
    })
  ];
}
