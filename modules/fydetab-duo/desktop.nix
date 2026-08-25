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

  kanshiBase = ''
    profile {
      output DSI-1 scale ${toString config.hardware.fydetabduo.display.scale}
    }
  '';
  kanshiLandscape = ''
    profile {
      output DSI-1 scale ${toString config.hardware.fydetabduo.display.scale} transform 270
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

      Mutually exclusive with sensors.autoRotate.
    '';
  };

  options.hardware.fydetabduo.display = {
    scale = lib.mkOption {
      type = lib.types.numbers.between 1.0 2.0;
      default = 1.25;
      description = ''
        Display scale factor for the DSI panel. The FydeTab Duo has a
        2000x1200 display at ~10.4 inches (~224 PPI). A scale of 1.25
        gives an effective 1600x960 logical resolution. Increase to 1.5
        for larger UI elements.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      hardware.graphics.enable = lib.mkDefault true;

      networking.networkmanager.wifi.macAddress = lib.mkDefault "permanent";
      networking.networkmanager.wifi.scanRandMacAddress = lib.mkDefault false;

      systemd.services."serial-getty@ttyFIQ0".enable = lib.mkDefault false;

      systemd.tmpfiles.rules = [
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
        # GTK4 dmabuf textures render black - Mesa panfrost cannot export panthor
        # exclusive-VM BOs (drmPrimeHandleToFD EINVAL). Remove when fixed in Mesa.
        GDK_DISABLE = "dmabuf";
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

      # kanshi: always write config with scale (transform added by landscape block)
      environment.etc."xdg/kanshi/config".text = kanshiBase;
      environment.etc."xdg/kanshi/greeter-config".text = kanshiBase;

      # labwc rc.xml: always active (keybinds, theme)
      environment.etc."xdg/labwc/rc.xml".text = ''
        <?xml version="1.0"?>
        <labwc_config>
          <theme>
            <name>FydeTab</name>
            <cornerradius>8</cornerradius>
          </theme>
          <keyboard>
            <default />
            <keybind key="W-Return"><action name="Execute" command="alacritty"/></keybind>
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

    (lib.mkIf cfg.landscape.enable {
      # Override kanshi config to include landscape transform
      environment.etc."xdg/kanshi/config".text = kanshiLandscape;
      environment.etc."xdg/kanshi/greeter-config".text = kanshiLandscape;

      # Add calibration matrix for landscape mode
      environment.etc."xdg/labwc/rc.xml".text = lib.mkForce ''
        <?xml version="1.0"?>
        <labwc_config>
          <theme>
            <name>FydeTab</name>
            <cornerradius>8</cornerradius>
          </theme>
          <keyboard>
            <default />
            <keybind key="W-Return"><action name="Execute" command="alacritty"/></keybind>
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
    })
  ];
}
