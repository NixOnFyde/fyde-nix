{
  ...
}:
{
  programs.vicinae = {
    enable = true;

    systemd = {
      autoStart = true;
      enable = true;
    };

    settings = {
      close_on_focus_loss = true;
      pop_to_root_on_close = true;
      pop_on_backspace = true;
      escape_key_behavior = "";

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
        opacity = 0.95;
        compact_mode = {
          enabled = false;
        };
      };

      providers = {
        clipboard.preferences = {
          encryption = true;
          eraseOnStartup = false;
          ignorePasswords = true;
          monitoring = true;
        };

        core = {
          entrypoints = {
            sponsor = {
              enabled = false;
            };
          };
        };

        developer = {
          enabled = false;
        };

        system = {
          entrypoints = {
            run = {
              alias = "cmd";
            };
            toggle-mute = {
              enabled = false;
            };
            volume-0 = {
              enabled = false;
            };
            volume-100 = {
              enabled = false;
            };
            volume-25 = {
              enabled = false;
            };
            volume-50 = {
              enabled = false;
            };
            volume-75 = {
              enabled = false;
            };
            volume-down = {
              enabled = false;
            };
            volume-up = {
              enabled = false;
            };
          };
        };

        power.entrypoints = {
          power-off.alias = "sd";
          reboot.alias = "rb";
          lock.alias = "lc";
        };

        theme = {
          enabled = false;
        };

        wm = {
          enabled = false;
        };
      };
    };
  };
}
