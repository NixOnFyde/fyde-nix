{
  config,
  lib,
  ...
}:
let
  shell = config.hardware.fydetabduo.shell;
in
{
  options.hardware.fydetabduo.shell.power.enable = lib.mkOption {
    type = lib.types.bool;
    default = shell.enable;
    description = ''
      Power management (upower + power-profiles-daemon for battery
      reporting). Defaults to following hardware.fydetabduo.shell.enable;
      set it independently to include or exclude just this part.
    '';
  };

  config = lib.mkIf shell.power.enable {
    # Power management (battery reporting for wayle)
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;

    # Physical power button (rk805 pwrkey): short press suspends (sleep),
    # long press still powers off. NixOS by default powers off on a short
    # press, which is wrong for a tablet.
    services.logind.settings.Login = {
      HandlePowerKey = "suspend";
      HandlePowerKeyLongPress = "poweroff";
    };
  };
}
