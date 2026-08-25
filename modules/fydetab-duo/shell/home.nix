{
  inputs,
  pkgs,
  ...
}:
let
  wallpaper = "/run/current-system/sw/share/backgrounds/fydetab-duo/wallpaper.jpg";
in
{
  imports = [ inputs.vicinae.homeManagerModules.default ];

  services.wayle = {
    enable = true;

    settings = {
      bar = {
        location = "top";
        scale = 0.65;
        spacing = 4;
        background-opacity = 5;
        button-bg-opacity = 50;
        button-variant = "basic";
        button-rounding = "none";
        layout = [
          {
            monitor = "DSI-1";
            left = [
              "dashboard"
              "window-title"
            ];
            center = [
              "cpu"
              "ram"
              "media"
            ];
            right = [
              "volume"
              "brightness"
              "network"
              "bluetooth"
              "battery"
              "systray"
              "clock"
              "notifications"
            ];
            show = true;
          }
          {
            monitor = "*"; # If somehow other monitors - e.g., HDMI over USB-C?
            show = false;
            left = [ ];
            center = [ ];
            right = [ ];
          }
        ];
      };

      general.font-sans = "Noto Sans";

      modules = {
        clock.format = "%a %d %b %H:%M";
        battery.low-threshold = 15;
        cpu.show-per-core = false;
      };

      styling = {
        rounding = "none";
        scale = 0.75;

        palette = {
          bg = "#0d0c0c";
          surface = "#181616";
          elevated = "#282727";
          fg = "#c5c9c5";
          fg-muted = "#a6a69c";
          primary = "#8992a7";
          blue = "#8ba4b0";
          green = "#87a987";
          yellow = "#c4b28a";
          red = "#c4746e";
        };
      };

      osd = {
        enable = true;
        timeout = 2000;
      };

      wallpaper = {
        engine-enabled = true;
        transition-type = "fade";
        transition-duration-ms = 500;

        monitors = [
          {
            name = "DSI-1";
            fit-mode = "fill";
            inherit wallpaper;
          }
        ];
      };
    };
  };

  programs.vicinae = {
    enable = true;

    systemd = {
      autoStart = true;
      enable = true;
    };

    settings = {
      close_on_focus_loss = true;
      pop_to_root_on_close = true;

      telemetry.system_info = false;

      favorites = [
        "system:run"
        "files:search"
        "clipboard:history"
        "power:power-off"
      ];

      font = {
        rendering = "native";
        normal.family = "Noto Sans";
      };

      launcher_window = {
        opacity = 0.97;
      };

      providers.clipboard.preferences = {
        monitoring = true;
        ignore_passwords = true;
        erase_on_startup = false;
      };

      providers.power.entrypoints = {
        power-off.alias = "sd";
        reboot.alias = "rb";
        lock.alias = "lc";
      };
    };
  };

  programs.ghostty = {
    enable = true;

    settings = {
      font-size = 11;
      gtk-single-instance = true;
      link-url = true;
      desktop-notifications = true;
    };
  };

  services.swayidle = {
    enable = true;
    systemdTargets = [ "graphical-session.target" ];

    timeouts = [
      {
        timeout = 600;
        command = "${pkgs.swaylock}/bin/swaylock -f -i ${wallpaper}";
      }
      {
        timeout = 900;
        command = "${pkgs.wlopm}/bin/wlopm --off '*'";
        resumeCommand = "${pkgs.wlopm}/bin/wlopm --on '*'";
      }
    ];

    events = {
      before-sleep = "${pkgs.swaylock}/bin/swaylock -f -i ${wallpaper}";
    };
  };
}
