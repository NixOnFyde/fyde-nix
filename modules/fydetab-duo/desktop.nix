{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.hardware.fydetabduo;
  pkgsUnstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.hostPlatform.system; };

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

      environment.systemPackages = [
        pkgs.bibata-cursors
        pkgs.regreet
      ];
      environment.sessionVariables = {
        __EGL_VENDOR_LIBRARY_DIRS = "/run/opengl-driver/share/glvnd/egl_vendor.d";
        XCURSOR_THEME = lib.mkDefault cursorTheme;
        XCURSOR_SIZE = lib.mkDefault cursorSize;
        # GTK4 dmabuf textures render black - Mesa panfrost cannot export panthor
        # exclusive-VM BOs (drmPrimeHandleToFD EINVAL). Remove when fixed in Mesa.
        GDK_DISABLE = "dmabuf";
      };

      # ReGreet greeter. Runs under our own labwc session so we reuse the panel
      # transform (kanshi) and touch/stylus mapping we already configure.
      programs.regreet = {
        enable = true;
        theme.name = "Adwaita-dark";
        iconTheme.name = "Papirus";
        cursorTheme = {
          name = cursorTheme;
          package = pkgs.bibata-cursors;
        };
        settings.GTK = {
          application_prefer_dark_theme = true;
        };
      };

      environment.etc."greetd/regreet.css".text = ''
        window {
          background-image: url("${pkgs.fydetab-wallpaper}/share/backgrounds/fydetab-duo/wallpaper.jpg");
          background-size: cover;
          background-position: center;
        }

        frame.background {
          background-color: rgba(0, 0, 0, 0.5);
          border: 1px solid rgba(255, 255, 255, 0.12);
          border-radius: 24px;
          padding: 16px;
        }

        label {
          color: rgba(255, 255, 255, 0.9);
        }

        entry, combobox {
          background-color: rgba(255, 255, 255, 0.1);
          border: 1px solid rgba(255, 255, 255, 0.25);
          border-radius: 10px;
          padding: 6px 10px;
          color: #ffffff;
          caret-color: #ffffff;
        }

        entry:focus, combobox:focus {
          border-color: rgba(255, 255, 255, 0.5);
          background-color: rgba(255, 255, 255, 0.14);
        }

        entry placeholder {
          color: rgba(255, 255, 255, 0.4);
        }

        combobox arrow {
          color: rgba(255, 255, 255, 0.6);
        }

        combobox window {
          background-color: rgba(30, 30, 30, 0.95);
          border: 1px solid rgba(255, 255, 255, 0.15);
          border-radius: 10px;
        }

        combobox window listview {
          background-color: transparent;
        }

        combobox window listview row {
          padding: 6px 10px;
          color: rgba(255, 255, 255, 0.85);
        }

        combobox window listview row:selected {
          background-color: rgba(255, 255, 255, 0.15);
          color: #ffffff;
        }

        togglebutton {
          background-color: rgba(255, 255, 255, 0.08);
          border: 1px solid rgba(255, 255, 255, 0.2);
          border-radius: 8px;
          padding: 4px;
          color: rgba(255, 255, 255, 0.7);
        }

        togglebutton:hover {
          background-color: rgba(255, 255, 255, 0.15);
          color: #ffffff;
        }

        togglebutton:checked {
          background-color: rgba(255, 255, 255, 0.2);
          border-color: rgba(255, 255, 255, 0.4);
          color: #ffffff;
        }

        button.suggested-action {
          background-color: rgba(99, 179, 237, 0.9);
          background-image: none;
          color: #ffffff;
          font-weight: bold;
          border: none;
          border-radius: 10px;
          padding: 8px 24px;
        }

        button.suggested-action:hover {
          background-color: rgba(99, 179, 237, 1.0);
        }

        button.suggested-action:active {
          background-color: rgba(66, 153, 225, 0.9);
        }

        button:not(.suggested-action):not(.destructive-action) {
          background-color: rgba(255, 255, 255, 0.1);
          color: rgba(255, 255, 255, 0.85);
          border: 1px solid rgba(255, 255, 255, 0.2);
          border-radius: 10px;
          padding: 8px 18px;
        }

        button:not(.suggested-action):not(.destructive-action):hover {
          background-color: rgba(255, 255, 255, 0.18);
        }

        button.destructive-action {
          background-color: rgba(229, 62, 62, 0.15);
          color: rgba(255, 150, 150, 0.9);
          border: 1px solid rgba(229, 62, 62, 0.25);
          border-radius: 10px;
          padding: 8px 18px;
        }

        button.destructive-action:hover {
          background-color: rgba(229, 62, 62, 0.3);
          color: #ffffff;
        }

        infobar {
          background-color: rgba(0, 0, 0, 0.6);
          border: 1px solid rgba(255, 255, 255, 0.15);
          border-radius: 10px;
          color: rgba(255, 255, 255, 0.9);
        }
      '';

      # labwc session for the greeter keeping our landscape/rotate + touch mapping.
      environment.etc."regreet-labwc/autostart".text = ''
        # Apply the same output transform the desktop shell gets (270 for
        # landscape, none for portrait) so the greeter renders upright.
        ${pkgs.kanshi}/bin/kanshi -c /etc/xdg/kanshi/greeter-config >/dev/null 2>&1 &

        # Wait for kanshi to actually apply the output transform so
        # touch/stylus mapping is correct from the start.
        for i in $(seq 1 10); do
          ${pkgs.wlr-randr}/bin/wlr-randr 2>/dev/null | grep -q "Transform: 270" && break
          sleep 0.1
        done

        # Launch the OSK so users can type their password on the
        # touchscreen. Skip if a USB keyboard is connected (HID
        # boot interface: class 03, subclass 01, protocol 01 = keyboard).
        has_kb=false

        for intf in /sys/bus/usb/devices/*:*.*; do
          [ -f "$intf/bInterfaceClass" ] || continue
          cls=$(cat "$intf/bInterfaceClass" 2>/dev/null)
          proto=$(cat "$intf/bInterfaceProtocol" 2>/dev/null)

          if [ "$cls" = "03" ] && [ "$proto" = "01" ]; then
            has_kb=true
            break
          fi
        done

        if [ "$has_kb" = false ]; then
          # Only spawn if NO keyboard connected
          ${pkgsUnstable.wvkbd}/bin/wvkbd-mobintl --hidden --auto -H 500 -L 400 -l full --landscape-layers landscape &
        fi

        # Manual toggle: spawn the OSK if not running, otherwise toggle
        # visibility. The greeter has no wayle/tablet-mode monitor, so this
        # gesture is the only way to get the OSK here. Mirrors the
        # tablet-mode gesture (killall -USR2 toggles if running, else spawn).
        ${pkgs.lisgd}/bin/lisgd -d /dev/input/event9 -o 3 -t 150 \
          -g "1,DU,B,*,R,${pkgs.toybox}/bin/killall -USR2 wvkbd-mobintl 2>/dev/null || ${pkgsUnstable.wvkbd}/bin/wvkbd-mobintl --hidden --auto -H 500 -L 400 -l full --landscape-layers landscape &" &

        # Launch ReGreet (blocking). When it exits (login succeeded), tear
        # down the compositor so greetd can start the real session.
        ${pkgs.regreet}/bin/regreet; kill %1 2>/dev/null; ${pkgs.labwc}/bin/labwc --exit
      '';

      environment.etc."regreet-labwc/rc.xml".text = ''
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
          ${touchMapToOutput}
        </labwc_config>
      '';

      services.greetd.settings.default_session.command =
        lib.mkForce "${pkgs.dbus}/bin/dbus-run-session ${pkgs.labwc}/bin/labwc -C /etc/regreet-labwc";

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
