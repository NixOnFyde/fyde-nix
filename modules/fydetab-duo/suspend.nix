{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo;

  wakeScreenHook = pkgs.writeShellScript "60-fydetab-wake-screen" ''
    # systemd-sleep runs hooks with a minimal PATH; coreutils has cat/head/sleep.
    export PATH=${pkgs.coreutils}/bin

    STATE=/run/fydetab-pwrkey-count

    count() {
        cat /sys/bus/platform/devices/rk805-pwrkey.*/wakeup/wakeup*/event_count 2>/dev/null | head -n1
    }

    case "$1" in
        pre)
            count > "$STATE"
            ;;
        post)
            [ -r "$STATE" ] || exit 0
            old=$(cat "$STATE")
            new=$(count)
            [ -n "$new" ] && [ "$new" != "$old" ] || exit 0
            ( sleep 1.5; ${lib.getExe pkgs.fydetab-wake-activity} ) >/dev/null 2>&1 &
            ;;
    esac
    exit 0
  '';
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

    wakeScreenFix.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Light the panel after power-key wakes by injecting one synthetic
        uinput key event (the pwrkey driver apparently swallows the real one).
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.deepSuspend.enable {
      boot.kernelParams = [ "mem_sleep_default=deep" ];

      systemd.sleep.settings.Sleep.SuspendState = "mem";
    })

    (lib.mkIf (cfg.deepSuspend.enable && cfg.wakeScreenFix.enable) {
      environment.etc."systemd/system-sleep/60-fydetab-wake-screen".source = wakeScreenHook;
    })
  ];
}
