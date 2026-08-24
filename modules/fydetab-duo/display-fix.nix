{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo.displayInitFix;

  fixDisplay = pkgs.writeShellScript "fydetab-fix-display" ''
    dir="/sys/class/graphics/fb0/"

    attempts=0
    while [ ! -d "$dir" ]; do
        sleep 1
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 30 ]; then
            echo "timed out waiting for $dir" >&2
            exit 1
        fi
    done

    printf 1 > "$dir/blank"
    printf 0 > "$dir/blank"
  '';
in
{
  options.hardware.fydetabduo.displayInitFix.enable = lib.mkOption {
    type = lib.types.bool;
    description = "Re-blank/un-blank fb0 once at sysinit to fix a black panel on some cold boots.";
  };

  config = lib.mkIf cfg.enable {
    systemd.services.fydetab-fix-display = {
      description = "Reinitialize the FydeTab Duo display";
      wantedBy = [ "sysinit.target" ];
      after = [ "systemd-modules-load.service" ];
      before = [
        "sysinit.target"
        "shutdown.target"
      ];
      conflicts = [ "shutdown.target" ];
      unitConfig.DefaultDependencies = false;

      serviceConfig = {
        Type = "oneshot";
        ExecStart = fixDisplay;
      };
    };
  };
}
