{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo.shell;
in
{
  options.hardware.fydetabduo.shell.enable = lib.mkEnableOption ''
    The default FydeTab Duo desktop shell with: labwc theming, root menu,
    wallpaper / keybind setup, keyring, polkit agent, and idle lock.

    Per-user components are provided as a Home Manager module; import
    `fyde-nix.homeManagerModules.default` into home-manager.sharedModules.
  '';

  config = lib.mkIf cfg.enable {
    # Desktop compositor & greeter
    programs.labwc.enable = true;
    programs.regreet.enable = true;
    programs.vicinae.input-server.enable = true;

    # Audio
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };

    # Desktop packages
    environment.systemPackages = with pkgs; [
      adwaita-icon-theme
      alsa-utils
      btop
      brightnessctl
      evtest
      fastfetch
      fydetab-wallpaper
      ghostty
      gnome-keyring
      grim
      hyprpolkitagent
      iio-sensor-proxy
      kanshi
      libinput
      librewolf
      mesa-demos
      papirus-icon-theme
      pulseaudio
      slurp
      swaylock
      thunar
      usb-modeswitch
      vulkan-tools
      wlopm
      wl-clipboard
      xdg-user-dirs
      yazi

      (pkgs.writeTextDir "share/themes/FydeTab/labwc/themerc" ''
        border.width: 1
        border.color: #2a2a2a
        cornerRadius: 8

        titlebar.height: 30
        padding.height: 6

        window.active.title.bg.color: #1c1c1e
        window.inactive.title.bg.color: #161618
        window.active.label.text.color: #e6e6ef
        window.inactive.label.text.color: #8a8a96
        window.active.label.text.font: "Noto Sans Bold 10"
        window.inactive.label.text.font: "Noto Sans 10"
        label.text.justify: center

        window.active.button.unpressed.image.color: #e6e6ef
        window.inactive.button.unpressed.image.color: #8a8a96

        background.color: #161618
        background.style: solid

        osd.bg.color: #1c1c1e
        osd.border.color: #2a2a2a
        osd.border.width: 1
        osd.window-switcher.background.color: #1c1c1e
        osd.window-switcher.item.active.background.color: #313134
        osd.window-switcher.width: 600
      '')
    ];

    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
      nerd-fonts.symbols-only
    ];

    environment.pathsToLink = [ "/share/backgrounds" ];

    environment.etc."xdg/labwc/menu.xml".text = ''
      <?xml version="1.0"?>
      <openbox_menu>
        <menu id="root-menu">
          <item label="Browser" icon="librewolf">
            <action name="Execute" command="librewolf"/>
          </item>
          <item label="Files" icon="system-file-manager">
            <action name="Execute" command="thunar"/>
          </item>
          <item label="Terminal" icon="utilities-terminal">
            <action name="Execute" command="ghostty"/>
          </item>
          <separator/>
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

    environment.etc."xdg/labwc/autostart".text =
      lib.optionalString config.hardware.fydetabduo.landscape.enable ''
        kanshi -c /etc/xdg/kanshi/config &
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
      "d /var/lib/regreet  0755 greeter greeter -"
      "d /var/log/regreet  0755 greeter greeter -"
      "d /tmp/.X11-unix   1777 root     root    -"
    ];
  };
}
