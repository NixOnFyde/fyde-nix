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

    # cpufreq_schedutil is built into this kernel (its Kconfig symbol is a
    # bool, not a tristate), but the cpuFreqGovernor option still adds it to
    # boot.kernelModules, so systemd-modules-load logged "Failed to find
    # module 'cpufreq_schedutil'" on every boot. Alias the name to the
    # built-in cpufreq core, which makes the modprobe a no-op. Plain
    # definition (not mkDefault) so it merges with the bluetooth module's
    # extraModprobeConfig.
    boot.extraModprobeConfig = "alias cpufreq_schedutil cpufreq";

    services.fstrim.enable = lib.mkDefault true;

    zramSwap.enable = lib.mkDefault true;
    zramSwap.algorithm = lib.mkDefault "zstd";

    services.earlyoom = {
      enable = lib.mkDefault true;
      enableNotifications = true;
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

    systemd.tmpfiles.rules = [
      "d /nix/var/nix/daemon-socket 0755 root root -"
    ];

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
