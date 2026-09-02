{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo.modem;
in
{
  options.hardware.fydetabduo.modem = {
    enable = lib.mkOption {
      type = lib.types.bool;
      description = ''
        Enable the inbuilt Quectel EM05-G LTE/4G modem. The M.2 slot is
        exposed as a plain USB 2.0 device (cdc-mbim / cdc-wdm), so the modem
        is detected automatically and needs no board-specific power handling;
        only ModemManager and a NetworkManager wwan integration are required.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    networking.modemmanager.enable = true;

    systemd.services.ModemManager.wantedBy = [ "multi-user.target" ];

    environment.systemPackages = [
      pkgs.modemmanager
      pkgs.modem-manager-gui
      pkgs.usbutils
    ];
  };
}
