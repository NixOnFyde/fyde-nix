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
      Keyring, polkit agent, PAM services (swaylock, greetd/login keyring),
      and the tmpfiles entries. Defaults to following
      hardware.fydetabduo.shell.enable; set it independently to include or
      exclude just this part.
    '';
  };

  config = lib.mkIf shell.security.enable {
    services.gnome.gnome-keyring.enable = true;

    systemd.user.services.hyprpolkitagent = {
      description = "Hyprpolkitagent - polkit authentication agent";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };

    security.pam.services.swaylock = { };

    security.pam.services.greetd.enableGnomeKeyring = true;
    security.pam.services.login.enableGnomeKeyring = true;

    systemd.tmpfiles.rules = [
      "d /var/lib/nwg-hello  0755 greeter greeter -"
      "d /var/log/nwg-hello  0755 greeter greeter -"
      "d /tmp/.X11-unix   1777 root     root    -"
      "d /nix/var/nix/daemon-socket 0755 root root -"
    ];
  };
}
