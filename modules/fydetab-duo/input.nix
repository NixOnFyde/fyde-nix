{
  config,
  lib,
  ...
}:
let
  cfg = config.hardware.fydetabduo.touchscreen;
in
{
  config = lib.mkIf cfg.enable {

    services.udev.extraHwdb = ''
      evdev:input:b0018v0000p0000e0000*
        EVDEV_ABS_00=::265
        EVDEV_ABS_01=::166
    '';
  };
}
