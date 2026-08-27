{
  config,
  lib,
  ...
}:
let
  shell = config.hardware.fydetabduo.shell;
in
{
  options.hardware.fydetabduo.shell.desktop.enable = lib.mkOption {
    type = lib.types.bool;
    default = shell.enable;
    description = ''
      The compositor & greeter parts of the desktop shell: labwc, nwg-hello,
      the vicinae input server, and the labwc menu/autostart/shutdown / GTK
      config files. Defaults to following hardware.fydetabduo.shell.enable;
      set it independently to include or exclude just this part.
    '';
  };

  config = lib.mkIf shell.desktop.enable {
    # Desktop compositor & greeter
    programs.labwc.enable = true;
    programs.vicinae.input-server.enable = true;

    # Link the .desktop session files into the store path that nwg-hello's
    # default session_dirs look up (/run/current-system/sw/share/...), so
    # the greeter's session list properly populates.
    environment.pathsToLink = [
      "/share/backgrounds"
      "/share/wayland-sessions"
    ];

    environment.etc."xdg/labwc/menu.xml".text = ''
      <?xml version="1.0"?>
      <openbox_menu>
        <menu id="root-menu">
          <item label="Launcher" icon="launch">
            <action name="Execute" command="vicinae toggle"/>
          </item>
          <separator/>
          <item label="Browser" icon="librewolf">
            <action name="Execute" command="librewolf"/>
          </item>
          <item label="Files" icon="system-file-manager">
            <action name="Execute" command="thunar"/>
          </item>
          <item label="Terminal" icon="utilities-terminal">
            <action name="Execute" command="alacritty"/>
          </item>
          <item label="Documents" icon="system-file-manager">
            <action name="Execute" command="evince"/>
          </item>
          <item label="Images" icon="image-viewer">
            <action name="Execute" command="gwenview"/>
          </item>
          <item label="Video" icon="multimedia-video-player">
            <action name="Execute" command="haruna"/>
          </item>
          <item label="System Monitor" icon="utilities-system-monitor">
            <action name="Execute" command="alacritty -e btop"/>
          </item>
          <separator/>
          <item label="Network" icon="network-wireless">
            <action name="Execute" command="alacritty -e nmtui"/>
          </item>
          <item label="Screenshot" icon="camera-photo">
            <action name="Execute" command="sh -c 'grim -g &quot;$(slurp)&quot; ~/Pictures/Screenshot-$(date +%s).png'"/>
          </item>
          <separator/>
          <item label="Log Out" icon="system-log-out">
            <action name="Exit"/>
          </item>
          <item label="Power Off" icon="system-shutdown">
            <action name="Execute" command="systemctl poweroff"/>
          </item>
        </menu>
      </openbox_menu>
    '';

    environment.etc."xdg/labwc/autostart".text = ''
      systemctl --user --no-block start labwc-session.target
      dbus-update-activation-environment --systemd --all
      kanshi -c /etc/xdg/kanshi/config &
    '';

    environment.etc."xdg/labwc/shutdown".text = ''
      systemctl --user stop graphical-session.target
    '';

    environment.etc."xdg/gtk-3.0/settings.ini".text = ''
      [Settings]
      gtk-icon-theme-name=Papirus
      gtk-theme-name=Adwaita-dark
    '';
    environment.etc."xdg/gtk-4.0/settings.ini".text = ''
      [Settings]
      gtk-icon-theme-name=Papirus
      gtk-theme-name=Adwaita-dark
    '';
  };
}
