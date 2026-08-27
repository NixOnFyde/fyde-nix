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

  # The DSI panel output name. The panel is natively portrait; landscape
  # applies a 270 transform via kanshi.
  panelName = "DSI-1";

  kanshiBase = ''
    profile {
      output ${panelName}
    }
  '';
  kanshiLandscape = ''
    profile {
      output ${panelName} transform 270
    }
  '';

  # Map the himax touchscreen and stylus to the panel output. wlroots
  # (via wlr_cursor) applies the output's CURRENT transform to mapped
  # touch/tablet devices, so input follows output rotation automagically -
  # under rot8, kanshi, or any wlr-randr transform - in every orientation.
  # This is compositor-agnostic within wlroots (labwc, sway, river, ...);
  # non-wlroots compositors (GNOME, KDE) map touch to outputs themselves.
  # Do NOT add a static libinput calibration matrix here: it cannot be
  # updated at runtime and breaks as soon as the output rotates.
  touchMapToOutput = ''
    <touch deviceName="himax-touchscreen" mapToOutput="${panelName}" />
    <tablet deviceName="himax-stylus" mapToOutput="${panelName}" />
  '';
in
{
  options.hardware.fydetabduo.landscape = {
    enable = lib.mkEnableOption ''
      Default landscape base for the DSI panel (which is natively portrait).
      Applies the transform through kanshi (wlr-output-management protocol,
      so it works under labwc, sway, niri, ... - anything supporting the
      protocol).

      Touch and stylus mapping to the panel output is handled separately
      (see touchMapToOutput above), so input follows the transform in any
      orientation.

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
        "d /nix/var/nix/daemon-socket 0755 root root -"
      ];

      boot.tmp.useTmpfs = lib.mkDefault true;

      nix.settings.experimental-features = lib.mkDefault [
        "nix-command"
        "flakes"
      ];

      systemd.sockets.dbus.wantedBy = [ "sockets.target" ];
      services.greetd.enable = true;
      systemd.services.greetd.after = [ "dbus.service" ];
      systemd.services.greetd.wants = [ "dbus.service" ];

      users.users.greeter.home = lib.mkDefault "/var/lib/nwg-hello";

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

      environment.systemPackages = [
        pkgs.bibata-cursors
        pkgs.nwg-hello
      ];
      environment.sessionVariables = {
        __EGL_VENDOR_LIBRARY_DIRS = "/run/opengl-driver/share/glvnd/egl_vendor.d";
        XCURSOR_THEME = lib.mkDefault cursorTheme;
        XCURSOR_SIZE = lib.mkDefault cursorSize;
        # GTK4 dmabuf textures render black - Mesa panfrost cannot export panthor
        # exclusive-VM BOs (drmPrimeHandleToFD EINVAL). Remove when fixed in Mesa.
        GDK_DISABLE = "dmabuf";
      };

      # nwg-hello greeter. Runs under its own labwc session so we reuse the panel
      # transform (kanshi) and touch/stylus mapping we already configure.
      environment.etc."nwg-hello/nwg-hello.json".source = pkgs.writeText "nwg-hello.json" (
        builtins.toJSON {
          # Point at the session files we provide via /etc and at the
          # system profile path so sessions installed as NixOS packages
          # (and linked via pathsToLink) are also discovered.
          session_dirs = [
            "/etc/nwg-hello/sessions"
            "/run/current-system/sw/share/wayland-sessions"
          ];
          custom_sessions = [ ];
          monitor_nums = [ ];
          form_on_monitors = [ ];
          delay_secs = 0;
          cmd-sleep = "systemctl suspend";
          cmd-reboot = "systemctl reboot";
          cmd-poweroff = "systemctl poweroff";
          gtk-theme = "Adwaita-dark";
          gtk-icon-theme = "Papirus";
          gtk-cursor-theme = cursorTheme;
          prefer-dark-theme = true;
          template-name = "";
          time-format = "%H:%M";
          date-format = "%A, %d %B";
          layer = "overlay";
          keyboard-mode = "on_demand";
          lang = "";
          avatar-show = false;
          avatar-size = 100;
          avatar-border-width = 1;
          avatar-border-color = "#eee";
          avatar-corner-radius = 15;
          avatar-circle = true;
          env-vars = [ ];
        }
      );

      # Provide the labwc session .desktop file for nwg-hello (and any
      # other greeter that scans wayland-sessions). NixOS doesn't always
      # link these into /run/current-system/sw so we do it ourselves.
      environment.etc."nwg-hello/sessions/labwc.desktop".text = ''
        [Desktop Entry]
        Name=labwc
        Comment=A wayland stacking compositor
        Exec=labwc
        Icon=labwc
        Type=Application
        DesktopNames=labwc;wlroots
      '';

      # Full-bleed FydeTab wallpaper.
      environment.etc."nwg-hello/nwg-hello.css".text = ''
        window {
          background-image: url("${pkgs.fydetab-wallpaper}/share/backgrounds/fydetab-duo/wallpaper.jpg");
          background-size: auto 100%;
        }

        #form-wrapper {
          background-color: rgba(0, 0, 0, 0.35);
          border-radius: 16px;
        }

        entry, button {
          background-color: rgba(255, 255, 255, 0.12);
          border: 1px solid rgba(255, 255, 255, 0.35);
          border-radius: 18px;
          padding: 12px;
          color: #ffffff;
        }

        button:hover { background-color: rgba(255, 255, 255, 0.22); }

        #power-button {
          border-radius: 18px;
          background: none;
          border: none;
        }
        #power-button:hover { background-color: rgba(255, 255, 255, 0.1); }

        #welcome-label { font-size: 40px; font-weight: bold; color: #ffffff; }
        #clock-label   { font-family: monospace; font-size: 26px; color: #ffffff; }
        #date-label    { font-family: monospace; font-size: 16px; color: rgba(255, 255, 255, 0.85); }
        #form-label    { color: #ffffff; }
      '';

      # labwc session for the greeter keeping our landscape/rotate + touch mapping.
      environment.etc."nwg-hello/labwc-config/autostart".text = ''
        # Apply the same output transform the desktop shell gets (270 for
        # landscape, none for portrait) so the greeter renders upright.
        ${pkgs.kanshi}/bin/kanshi -c /etc/xdg/kanshi/greeter-config >/dev/null 2>&1 &

        # Run nwg-hello in the foreground; once it exits (a user logged in)
        # tear the compositor down so greetd starts the actual session.
        exec ${pkgs.nwg-hello}/bin/nwg-hello -c /etc/nwg-hello/nwg-hello.json -s /etc/nwg-hello/nwg-hello.css; ${pkgs.labwc}/bin/labwc --exit
      '';

      environment.etc."nwg-hello/labwc-config/rc.xml".text = ''
        <?xml version="1.0"?>
        <labwc_config>
          <theme>
            <name>FydeTab</name>
            <cornerradius>8</cornerradius>
          </theme>
          ${touchMapToOutput}
        </labwc_config>
      '';

      services.greetd.settings.default_session.command =
        lib.mkForce "${pkgs.dbus}/bin/dbus-run-session ${pkgs.labwc}/bin/labwc -C /etc/nwg-hello/labwc-config";

      environment.etc."xdg/kanshi/config".text = kanshiBase;
      environment.etc."xdg/kanshi/greeter-config".text = kanshiBase;

      # labwc rc.xml: always active (keybinds, theme)
      environment.etc."xdg/labwc/rc.xml".text = ''
        <?xml version="1.0"?>
        <labwc_config>
          <theme>
            <name>FydeTab</name>
            <icon>Papirus</icon>
            <cornerradius>8</cornerradius>
          </theme>
          <menu>
            <showIcons>yes</showIcons>
          </menu>
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
          ${touchMapToOutput}
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
            <icon>Papirus</icon>
            <cornerradius>8</cornerradius>
          </theme>
          <menu>
            <showIcons>yes</showIcons>
          </menu>
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
          ${touchMapToOutput}
        </labwc_config>
      '';
    })
  ];
}
