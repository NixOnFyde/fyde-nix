{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo.sensors;
  rot8-wrapper = pkgs.writeShellScript "rot8-wrapper" ''
    export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-0}"
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

    # rot8 detects the compositor by calling out to `pidof` (procps) and
    # panics at startup if it can't be found. NixOS injects a minimal PATH
    # (coreutils/findutils/grep/sed/systemd) into systemd.user.services
    # units, so we need to provide one that includes procps ourselves.
    export PATH="${lib.makeBinPath [ pkgs.procps ]}"

    # The panel output name (DSI-1; rot8 defaults to eDP-1 and then just
    # never rotates). -n 1008: lis2dw12 raw LSB per g (1/0.009571).
    # -Y: flip y to match ACCEL_MOUNT_MATRIX (device_y = -sensor_y).
    exec ${lib.getExe pkgs.rot8} -d DSI-1 -n 1008 -Y
  '';
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

      Touch and stylus follow the output rotation as long as the compositor
      maps them to the panel output: wlroots applies the output transform to
      mapped input devices, so input rotates together with the screen in every
      orientation. labwc gets this mapping from the panel output (see
      desktop.nix); sway uses `map_to_output`, and GNOME/KDE map touch
      automatically.

      Can be used alongside landscape.enable: kanshi applies the landscape
      transform at startup, rot8 overrides it dynamically when the device
      is rotated.
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
          Type = "simple";
          ExecStart = rot8-wrapper;
          Restart = "on-failure";
          RestartSec = 10;
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
