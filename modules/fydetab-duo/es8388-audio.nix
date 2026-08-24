{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo.audio;
in
{
  options.hardware.fydetabduo.audio.enable = lib.mkOption {
    type = lib.types.bool;
    description = ''
      Enable the ES8388 codec routing fixes: restore the analog playback
      switches at boot and make WirePlumber prefer the codec as default
      output (when PipeWire/WirePlumber is enabled).
    '';
  };

  config = lib.mkIf cfg.enable {
    systemd.services.fydetab-es8388-routing = {
      description = "Restore ES8388 analog playback routing";
      after = [ "sound.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart =
          let
            amixer = "${lib.getExe' pkgs.alsa-utils "amixer"} -c rockchipes8388";
          in
          pkgs.writeShellScript "fydetab-es8388-routing" ''
            timeout=30
            while ! ${amixer} info > /dev/null 2>&1; do
              [ "$timeout" -le 0 ] && {
                echo "rockchipes8388 card never appeared" >&2
                exit 0
              }
              sleep 1
              timeout=$((timeout - 1))
            done

            ${amixer} sset 'spk switch'       on
            ${amixer} sset 'hp switch'        on
            ${amixer} sset 'Speaker'          on
            ${amixer} sset 'Headphone'        on
            ${amixer} sset 'Left Mixer Left'  on
            ${amixer} sset 'Right Mixer Right' on
            ${amixer} sset 'OUT1'             on
            ${amixer} sset 'OUT2'             on
            ${amixer} sset 'PCM'              85%
            ${amixer} sset 'Output 1'         85%
            ${amixer} sset 'Output 2'         85%
          '';
      };
    };

    services.pipewire.wireplumber.extraConfig = lib.mkIf config.services.pipewire.enable {
      "60-fydetab-es8388" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              {
                node.name = "~alsa_output\\.platform-es8388-sound\\..*";
              }
            ];
            actions.update-props = {
              node.description = "FydeTab Duo Speakers/Headphones";
              node.nick = "ES8388";

              priority.session = 100;
            };
          }
        ];
      };
    };

    systemd.user.services.fydetab-default-sink = lib.mkIf config.services.pipewire.enable {
      description = "Pin default audio sink to the ES8388 analog output";
      wantedBy = [ "default.target" ];
      after = [ "pipewire.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart =
          let
            wpctl = lib.getExe' pkgs.pipewire "wpctl";
          in
          pkgs.writeShellScript "fydetab-default-sink" ''
            for i in $(seq 1 45); do
              id=$(${wpctl} status 2>/dev/null |
                sed -n "s/^[[:space:]]*\\([0-9][0-9]*\\)\\. alsa_output\\.platform-es8388[^ ]*/\\1/p" | head -1)
              if [ -n "$id" ]; then
                ${wpctl} set-default "$id" && exit 0
              fi
              sleep 2
            done
            echo "es8388 sink never appeared; leaving default untouched" >&2
            exit 0
          '';
      };
    };
  };
}
