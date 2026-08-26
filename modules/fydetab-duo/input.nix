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

    # Grant the active seat session (greeter + user) access to the himax
    # touch/stylus devices. TAG+="uaccess" relies on logind which is async
    # and can be slow. Users should also be in the "input" group for instant
    # access via Unix group permissions (devices are root:input 0660).
    services.udev.extraRules = ''
      KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="himax-touchscreen", TAG+="uaccess"
      KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="himax-stylus", TAG+="uaccess"
    '';
  };
}
