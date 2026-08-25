{
  config,
  lib,
  ...
}:
let
  shell = config.hardware.fydetabduo.shell;
in
{
  options.hardware.fydetabduo.shell.audio.enable = lib.mkOption {
    type = lib.types.bool;
    default = shell.enable;
    description = ''
      The pipewire audio stack and rtkit. Defaults to following
      hardware.fydetabduo.shell.enable; set it independently to include or
      exclude just this part.
    '';
  };

  config = lib.mkIf shell.audio.enable {
    # Audio
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };
  };
}
