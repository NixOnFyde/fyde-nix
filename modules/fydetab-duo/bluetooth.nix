{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo.bluetooth;

  patchram = pkgs.writeShellScript "fydetab-bluetooth-init" ''
    set -u

    ${lib.getExe' pkgs.util-linux "rfkill"} block bluetooth
    sleep 2
    ${lib.getExe' pkgs.util-linux "rfkill"} unblock bluetooth
    sleep 2

    exec ${lib.getExe pkgs.brcm-patchram-plus} \
      --enable_hci --no2bytes --use_baudrate_for_download --tosleep 200000 \
      --baudrate 1500000 \
      --patchram ${pkgs.ap6275p-firmware}/lib/firmware/ap6275p/BCM4362A2.hcd \
      /dev/ttyS9
  '';
in
{
  options.hardware.fydetabduo.bluetooth.enable = lib.mkOption {
    type = lib.types.bool;
    description = "Init the AP6275P Bluetooth over /dev/ttyS9 with brcm_patchram_plus.";
  };

  config = lib.mkIf cfg.enable {
    boot = {
      kernelModules = [ "hci_uart" ];
      extraModprobeConfig = ''
        # Prevents the bluetooth module from entering aggressive low-power sleep states
        options bluetooth disable_ertm=1
      '';
    };

    services.pipewire.wireplumber.extraConfig.bluetoothEnhancements = {
      "monitor.bluez.properties" = {
        "bluez5.enable-sbc-xq" = true;
        "bluez5.enable-msbc" = true;
        "bluez5.enable-hw-volume" = true;
        "bluez5.roles" = [ "a2dp_sink" ]; # Prioritise high-quality playback
      };
    };

    systemd.services.fydetab-bluetooth = {
      description = "FydeTab Duo Bluetooth firmware loader";
      bindsTo = [ "dev-ttyS9.device" ];
      after = [ "dev-ttyS9.device" ];
      before = [ "bluetooth.service" ];
      wantedBy = [ "multi-user.target" ];

      unitConfig = {
        StartLimitIntervalSec = 0;
      };

      serviceConfig = {
        Type = "simple";

        ExecStartPre = "${lib.getExe' pkgs.kmod "modprobe"} bluetooth";
        ExecStart = patchram;
        Restart = "on-failure";
        RestartSec = "3s";
      };
    };

    hardware.bluetooth = {
      enable = lib.mkDefault true;

      powerOnBoot = true;
      settings = {
        General = {
          Experimental = true;
        };
      };
    };
  };
}
