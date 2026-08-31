{
  config,
  lib,
  pkgs,
  ...
}:
let
  shell = config.hardware.fydetabduo.shell;
in
{
  options.hardware.fydetabduo.shell.security.enable = lib.mkOption {
    type = lib.types.bool;
    default = shell.enable;
    description = ''
      Keyring (gnome-keyring), polkit agent (lxqt-policykit-agent), and
      login PAM keyring unlock. Defaults to following
      hardware.fydetabduo.shell.enable; set it independently to include or
      exclude just this part.

      Note: screen lock PAM (swaylock) is configured by the swayidle home
      manager module, and greeter PAM is configured by the desktop module.
    '';
  };

  config = lib.mkIf shell.security.enable {
    services.gnome.gnome-keyring.enable = true;

    systemd.user.services.lxqt-policykit-agent = {
      description = "LXQt polkit authentication agent";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.lxqt.lxqt-policykit-agent}/libexec/lxqt-policykit-agent";
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };

    security.pam.services.login.enableGnomeKeyring = true;
  };
}
