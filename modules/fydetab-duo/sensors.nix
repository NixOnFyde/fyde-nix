{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo.sensors;
in
{
  options.hardware.fydetabduo.sensors.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable the ST lis2dw12 accelerometer (mount matrix) and iio-sensor-proxy.";
  };

  options.hardware.fydetabduo.sensors.autoRotate = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Start rot8 in every graphical session: reads the lis2dw12 through
      iio-sensor-proxy and rotates outputs via wlr-randr (wlr-output-management),
      so it works under labwc, sway, river, niri - any wlroots compositor.

      EXPERIMENTAL: the shipped touch calibration matrix assumes landscape
      only; in other orientations touch mapping may be off unless your
      compositor maps touch to output itself. Mutually exclusive with
      hardware.fydetabduo.landscape.enable (which pins as landscape).
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      hardware.sensor.iio.enable = true;

      services.udev.extraRules = ''
        SUBSYSTEM=="iio", ATTR{name}=="lis2dw12", ENV{ACCEL_MOUNT_MATRIX}="1,0,0;0,-1,0;0,0,1"
      '';
    })

    (lib.mkIf config.hardware.fydetabduo.sensors.autoRotate {
      environment.systemPackages = [
        pkgs.rot8
        pkgs.wlr-randr
      ];

      systemd.user.services.rot8 = {
        description = "Auto-rotate outputs from the accelerometer";
        wantedBy = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = lib.getExe pkgs.rot8;
          Restart = "on-failure";
          RestartSec = 5;
        };
      };
    })
  ];
}
