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
    # touch/stylus devices. Without uaccess, logind only hands them to the
    # first process that opens them - which can be root via logind itself,
    # leaving the compositor's session unable to get touch events.
    services.udev.extraRules = ''
      KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="himax-touchscreen", TAG+="uaccess"
      KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="himax-stylus", TAG+="uaccess"
    '';
  };
}
