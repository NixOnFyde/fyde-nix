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
  options.hardware.fydetabduo.shell.packages.enable = lib.mkOption {
    type = lib.types.bool;
    default = shell.enable;
    description = ''
      Desktop application packages, fonts, the labwc themerc, and the
      .nix mimetype bound to Zed. Defaults to following
      hardware.fydetabduo.shell.enable; set it independently to include or
      exclude just this part.
    '';
  };

  config = lib.mkIf shell.packages.enable {
    environment.systemPackages = with pkgs; [
      # Register text/x-nix so .nix files get their own mimetype instead of
      # going into text/plain (which LibreWolf controls on first run).
      (pkgs.writeTextDir "share/mime/packages/nix.xml" ''
        <?xml version="1.0" encoding="UTF-8"?>
        <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
          <mime-type type="text/x-nix">
            <comment>Nix expression</comment>
            <glob pattern="*.nix"/>
          </mime-type>
        </mime-info>
      '')
      adwaita-icon-theme
      alsa-utils
      btop
      brightnessctl
      evtest
      evince
      fastfetch
      alacritty
      fydetab-update
      fydetab-wallpaper
      gnome-keyring
      grim
      haruna
      helix
      lxqt.lxqt-policykit
      iio-sensor-proxy
      kdePackages.gwenview
      kanshi
      libinput
      libnotify
      librewolf
      mesa-demos
      papirus-icon-theme
      kdePackages.partitionmanager
      pulseaudio
      slurp
      # Blur-capable drop-in for swaylock (used by swayidle lock cmd)
      swaylock-effects
      thunar
      usb-modeswitch
      vulkan-tools
      wlopm
      wl-clipboard
      xdg-user-dirs
      yazi
      zed-editor

      (pkgs.writeTextDir "share/themes/FydeTab/labwc/themerc" ''
        border.width: 1
        border.color: #2a2a2a
        cornerRadius: 8

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

    # Open .nix files in Zed (GUI editor) rather than falling back to
    # LibreWolf using the text/plain association.
    xdg.mime.defaultApplications = {
      "text/x-nix" = [ "dev.zed.Zed.desktop" ];
    };

    fonts.packages = with pkgs; [
      jetbrains-mono
      noto-fonts
      noto-fonts-color-emoji
      nerd-fonts.symbols-only
    ];
  };
}
