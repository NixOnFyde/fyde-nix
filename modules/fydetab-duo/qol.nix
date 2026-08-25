{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo.qol;
in
{
  options.hardware.fydetabduo.qol.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Enable FydeTab Duo QOL defaults: schedutil CPU governor,
      weekly fstrim, persistent journald (CoW-disabled), nix daemon socket
      dir creation, XDG user directories per session, WiFi powersave off,
      zram swap, and a manual fydetab-debug-dump unit.
    '';
  };

  config = lib.mkIf cfg.enable {
    powerManagement.cpuFreqGovernor = lib.mkDefault "schedutil";

    services.fstrim.enable = lib.mkDefault true;

    zramSwap.enable = lib.mkDefault true;
    zramSwap.algorithm = lib.mkDefault "zstd";

    systemd.services.zram-shutdown = {
      description = "Forcefully deactivate zram swap before shutdown";
      unitConfig.DefaultDependencies = false;
      before = [ "shutdown.target" ];
      wantedBy = [ "shutdown.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = [
          "${pkgs.kmod}/bin/modprobe -r zram"
        ];
        RemainAfterExit = true;
        TimeoutSec = 5;
      };
    };

    networking.networkmanager.wifi.powersave = lib.mkDefault false;

    systemd.user.services.xdg-user-dirs-update = {
      description = "Initialize XDG user directories";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.xdg-user-dirs}/bin/xdg-user-dirs-update";
      };
    };

    system.activationScripts.fydetabStateDirs.text = ''
      mkdir -p /var/log/journal
      chattr +C /var/log/journal 2>/dev/null || true
      mkdir -p /nix/var/nix/daemon-socket
    '';

    systemd.services.fydetab-debug-dump = {
      description = "Dump boot diagnostics to the ESP";
      unitConfig.ConditionPathExists = "/boot";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.runCommand "fydetab-debug-dump" { } ''
          cp ${../../scripts/fydetab-debug-dump.sh} $out
          chmod +x $out
        ''}";
      };
    };
  };
}
