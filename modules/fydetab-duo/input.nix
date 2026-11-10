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

    # Resolution is in units per mm. The panel is 166 x 266 mm, and the
    # stylus range is 10 times the touch range.
    services.udev.extraHwdb = ''
      evdev:name:himax-touchscreen:*
        EVDEV_ABS_00=::10
        EVDEV_ABS_01=::10
        EVDEV_ABS_35=::10
        EVDEV_ABS_36=::10

      evdev:name:himax-stylus:*
        EVDEV_ABS_00=::96
        EVDEV_ABS_01=::96
    '';

    # Grant the active seat session (greeter + user) access to the himax
    # touch/stylus devices. TAG+="uaccess" relies on logind which is async
    # and can be slow. The greeter is also added to the "input" group for
    # instant access through Unix group permissions (devices are root:input
    # 0660), bypassing the logind timing dependency entirely.
    users.users.greeter.extraGroups = [ "input" ];

    services.udev.extraRules = ''
      KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="himax-touchscreen", SYMLINK+="input/himax-touchscreen", TAG+="uaccess"
      KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="himax-stylus", SYMLINK+="input/himax-stylus", TAG+="uaccess"
    '';
  };
}
