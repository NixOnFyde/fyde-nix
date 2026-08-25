{
  pkgs,
  ...
}:
let
  # swaylock-effects provides a drop-in `swaylock` binary with blur effects.
  # Lock with a blurred screenshot of the current screen - not a static
  # wallpaper. Note to self - keep as a single line: HM inlines it into the
  # swayidle systemd unit, which will reject embedded newlines.
  lockCmd = "${pkgs.swaylock-effects}/bin/swaylock -f --screenshots --effect-blur 7x5";
in
{
  services.swayidle = {
    enable = true;
    systemdTargets = [ "graphical-session.target" ];

    timeouts = [
      {
        timeout = 600;
        command = lockCmd;
      }
      {
        timeout = 900;
        command = "${pkgs.wlopm}/bin/wlopm --off '*'";
        resumeCommand = "${pkgs.wlopm}/bin/wlopm --on '*'";
      }
    ];

    events = {
      before-sleep = lockCmd;
    };
  };
}
