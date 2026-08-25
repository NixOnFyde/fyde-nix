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

      Can be used alongside landscape.enable: kanshi applies the landscape
      transform at startup, rot8 overrides it dynamically when the device
      is rotated. Touch mapping is handled by wlr-output-management.
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
          Environment = [
            "WAYLAND_DISPLAY=wayland-0"
            "XDG_RUNTIME_DIR=/run/user/%U"
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus"
          ];
        };
      };

      # Allow users in wheel to claim iio-sensor-proxy without polkit auth
      environment.etc."polkit-1/rules.d/50-iio-sensor-proxy.rules".text = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.sensors.claim" &&
              subject.isInGroup("wheel")) {
            return polkit.Result.YES;
          }
        });
      '';
    })
  ];
}
