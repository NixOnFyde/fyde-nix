{
  config,
  lib,
  ...
}: let
  cfg = config.hardware.fydetabduo.touchscreen;
in {
  config = lib.mkIf cfg.enable {
    services.udev.extraRules = ''
      SUBSYSTEM=="input", ENV{ID_INPUT_TABLET}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="0 1 0 -1 0 1 0 0 1"
    '';

    services.udev.extraHwdb = ''
      evdev:input:b0018v0000p0000e0000*
        EVDEV_ABS_00=::265
        EVDEV_ABS_01=::166
    '';
  };
}
