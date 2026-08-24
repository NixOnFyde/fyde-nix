{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo;

  cursorTheme = "Bibata-Modern-Ice";
  cursorSize = "24";

  kanshiLandscape = ''
    profile {
      output DSI-1 transform 270
    }
  '';
  labwcCalibrationMatrix = "0 1 0 -1 0 1";
in
{
  options.hardware.fydetabduo.landscape = {
    enable = lib.mkEnableOption ''
      Default landscape base for the DSI panel (which is natively portrait).
      Applies the transform through kanshi (wlr-output-management protocol,
      so it works under labwc, sway, niri, ... - anything supporting the
      protocol), and the matching himax touchscreen calibration for
      compositors without native touch-to-output mapping (labwc).

      Compositors with built-in output handling (e.g., niri, GNOME, KDE) can
      disable this and configure rotation themselves.
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      hardware.graphics.enable = lib.mkDefault true;

      networking.networkmanager.wifi.macAddress = lib.mkDefault "permanent";
      networking.networkmanager.wifi.scanRandMacAddress = lib.mkDefault false;

      systemd.services."serial-getty@ttyFIQ0".enable = lib.mkDefault false;

      systemd.tmpfiles.rules = [
        "d /var/lib/regreet 0755 greeter greeter -"
        "d /var/log/regreet 0755 greeter greeter -"

        "d /tmp/.X11-unix 1777 root root -"

        "d /nix/var/nix/daemon-socket 0755 root root -"
      ];

      boot.tmp.useTmpfs = lib.mkDefault true;

      nix.settings.experimental-features = lib.mkDefault [
        "nix-command"
        "flakes"
      ];

      systemd.sockets.dbus.wantedBy = [ "sockets.target" ];
      systemd.services.greetd.after = [ "dbus.service" ];
      systemd.services.greetd.wants = [ "dbus.service" ];

      systemd.services.greetd.environment.XDG_DATA_DIRS =
        lib.mkDefault "${config.services.displayManager.sessionData.desktops}/share";

      users.users.greeter.home = lib.mkDefault "/var/lib/regreet";

      systemd.services.fydetab-opengl-link = {
        description = "Ensure /run/opengl-driver points at Mesa";
        wantedBy = [ "graphical.target" ];
        before = [
          "greetd.service"
          "display-manager.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "fydetab-opengl-link" ''
            ln -sfn ${pkgs.mesa} /run/opengl-driver
          '';
        };
      };

      systemd.services.accounts-daemon.after = [ "systemd-logind.service" ];

      environment.systemPackages = [ pkgs.bibata-cursors ];
      environment.sessionVariables = {
        __EGL_VENDOR_LIBRARY_DIRS = "/run/opengl-driver/share/glvnd/egl_vendor.d";
        XCURSOR_THEME = lib.mkDefault cursorTheme;
        XCURSOR_SIZE = lib.mkDefault cursorSize;
      };

      programs.regreet.settings = {
        GTK = {
          cursor_theme = cursorTheme;
          icon_theme = "Papirus";
          theme = "Adwaita-dark";
          application_prefer_dark_theme = true;
        };
        appearance = {
          background = "${pkgs.fydetab-wallpaper}/share/backgrounds/fydetab-duo/wallpaper.jpg";
          background_fit = "Cover";
        };
        commands = {
          reboot = [
            "systemctl"
            "reboot"
          ];
          poweroff = [
            "systemctl"
            "poweroff"
          ];
        };
      };

      services.greetd.settings.default_session.command =
        let
          greetd-start = pkgs.writeShellScript "fydetab-greetd-start" ''
            ${pkgs.kanshi}/bin/kanshi -c /etc/xdg/kanshi/greeter-config >/dev/null 2>&1 &
            exec ${pkgs.regreet}/bin/regreet
          '';
        in
        lib.mkForce "${pkgs.dbus}/bin/dbus-run-session ${pkgs.labwc}/bin/labwc -C /etc/xdg/labwc-greeter -S ${greetd-start}";
    })

    (lib.mkIf cfg.landscape.enable {
      environment.etc."xdg/kanshi/config".text = kanshiLandscape;
      environment.etc."xdg/kanshi/greeter-config".text = kanshiLandscape;

      environment.etc."xdg/labwc/rc.xml".text = ''
        <?xml version="1.0"?>
        <labwc_config>
          <theme>
            <name>FydeTab</name>
            <cornerradius>8</cornerradius>
          </theme>
          <keyboard>
            <default />
            <keybind key="W-Return"><action name="Execute" command="ghostty"/></keybind>
            <keybind key="W-d"><action name="Execute" command="vicinae toggle"/></keybind>
            <keybind key="Print"><action name="Execute" command="sh -c 'mkdir -p $HOME/Pictures &amp;&amp; grim -g &quot;$(slurp)&quot; $HOME/Pictures/Screenshot-$(date +%s).png'"/></keybind>
            <keybind key="XF86AudioRaiseVolume">
              <action name="Execute" command="wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.0"/>
            </keybind>
            <keybind key="XF86AudioLowerVolume">
              <action name="Execute" command="wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"/>
            </keybind>
            <keybind key="XF86AudioMute">
              <action name="Execute" command="wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"/>
            </keybind>
            <keybind key="XF86MonBrightnessUp">
              <action name="Execute" command="brightnessctl s +5%"/>
            </keybind>
            <keybind key="XF86MonBrightnessDown">
              <action name="Execute" command="brightnessctl s 5%-"/>
            </keybind>
          </keyboard>
          <libinput>
            <device category="himax-touchscreen">
              <calibrationMatrix>${labwcCalibrationMatrix}</calibrationMatrix>
            </device>
          </libinput>
        </labwc_config>
      '';
      environment.etc."xdg/labwc-greeter/rc.xml".text = ''
        <?xml version="1.0"?>
        <labwc_config>
          <libinput>
            <device category="himax-touchscreen">
              <calibrationMatrix>${labwcCalibrationMatrix}</calibrationMatrix>
            </device>
          </libinput>
        </labwc_config>
      '';
    })
  ];
}
