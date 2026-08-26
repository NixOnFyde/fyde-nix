{
  lib,
  pkgs,
  config,
  ...
}:
let
  wallpaper = "/run/current-system/sw/share/backgrounds/fydetab-duo/wallpaper.jpg";
  weather = config.fydetabShell.wayle.weather;
in
{
  options.fydetabShell.wayle.weather = {
    latitude = lib.mkOption {
      type = lib.types.nullOr lib.types.float;
      default = null;
      description = ''
        Latitude for the wayle weather module, e.g. 51.5 for London.
        Left null, wayle falls back to its built-in default location.
      '';
    };
    longitude = lib.mkOption {
      type = lib.types.nullOr lib.types.float;
      default = null;
      description = ''
        Longitude for the wayle weather module, e.g. -0.1 for London.
        Left null, wayle falls back to its built-in default location.
      '';
    };
  };

  config = {
    services.wayle = {
      enable = true;

      settings = {
        bar = {
          location = "top";
          scale = 0.80;
          module-gap = 0.5;
          background-opacity = 5;
          button-bg-opacity = 50;
          button-label-size = 1.15;
          button-label-weight = "bold";
          button-variant = "basic";
          button-rounding = "none";
          dropdown-opacity = 95;
          layout = [
            {
              monitor = "DSI-1";
              left = [
                "dashboard"
                "custom-performance"
                "custom-auto-rotate"
                "custom-tablet-mode"
              ];
              center = [
                "cpu"
                "ram"
                "custom-storage"
                "weather"
              ];
              right = [
                "systray"
                "volume"
                "microphone"
                "brightness"
                "network"
                "bluetooth"
                "battery"
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

        general.font-sans = "JetBrains Mono";

        modules = {
          dashboard.icon-color = "blue";

          clock = {
            format = "%a %d %b %H:%M";
            icon-show = false;
            label-color = "fg-default";
          };

          battery = {
            low-threshold = 15;
            icon-color = "fg-default";
            label-color = "fg-default";
          };

          cpu = {
            format = "{{ percent }}% @{{ temp_c }}C @{{ freq_ghz }}GHz";
            show-per-core = false;

            # wayle's auto temp detection only knows x86 sensor names
            # (coretemp/k10temp/...), so we point it at the RK3588's
            # package_thermal hwmon entry.
            temp-sensor = "package";
            poll-interval-ms = 5000;
            icon-color = "fg-default";
            label-color = "fg-default";
            thresholds = [
              {
                above = 70;
                icon-color = "status-warning";
                label-color = "status-warning";
              }
              {
                above = 90;
                icon-color = "status-error";
                label-color = "status-error";
              }
            ];
          };

          ram = {
            format = "{{ percent }}%+{{ swap_percent }}%";
            poll-interval-ms = 5000;
            icon-color = "fg-default";
            label-color = "fg-default";
            thresholds = [
              {
                above = 80;
                icon-color = "status-warning";
                label-color = "status-warning";
              }
              {
                above = 95;
                icon-color = "status-error";
                label-color = "status-error";
              }
            ];
          };

          volume = {
            icon-color = "fg-default";
            label-color = "fg-default";
            scroll-up = "wayle audio output-volume +2";
            scroll-down = "wayle audio output-volume -2";
            thresholds = [
              {
                above = 80;
                icon-color = "status-warning";
                label-color = "status-warning";
              }
              {
                above = 90;
                icon-color = "status-error";
                label-color = "status-error";
              }
            ];
          };

          microphone = {
            icon-color = "fg-default";
            label-color = "fg-default";
            scroll-up = "wayle audio input-volume +2";
            scroll-down = "wayle audio input-volume -2";
            thresholds = [
              {
                above = 70;
                icon-color = "status-warning";
                label-color = "status-warning";
              }
              {
                above = 90;
                icon-color = "status-error";
                label-color = "status-error";
              }
            ];
          };

          brightness = {
            icon-color = "fg-default";
            label-color = "fg-default";
          };

          network = {
            icon-color = "fg-default";
            label-color = "fg-default";
          };

          bluetooth = {
            icon-color = "fg-default";
            label-color = "fg-default";
          };

          systray = {
            border-show = true;
            button-bg-color = "accent-hover";
            icon-scale = 1.4;
          };

          notifications = {
            icon-color = "fg-default";
            label-color = "fg-default";
            thresholds = [
              {
                above = 5;
                icon-color = "status-warning";
                label-color = "status-warning";
              }
              {
                above = 20;
                icon-color = "status-error";
                label-color = "status-error";
              }
            ];
          };

          weather = {
            icon-color = "status-warning";
            label-color = "status-warning";
            time-format = "24h";
          }
          // lib.optionalAttrs (weather.latitude != null && weather.longitude != null) {
            location = "${toString weather.latitude},${toString weather.longitude}";
          };

          custom = [
            {
              id = "auto-rotate";
              interval-ms = 3000;
              command = ''systemctl --user is-active rot8 >/dev/null 2>&1 && printf '{"state":"On"}' || printf '{"state":"Off"}' '';
              left-click = ''
                if systemctl --user is-active rot8 >/dev/null 2>&1; then
                  systemctl --user stop rot8
                  notify-send -a wayle -u low -t 2500 "Auto-rotate" "Auto-rotate disabling..."
                else
                  systemctl --user start rot8
                  notify-send -a wayle -u low -t 2500 "Auto-rotate" "Auto-rotate enabling..."
                fi
              '';
              on-action = ''systemctl --user is-active rot8 >/dev/null 2>&1 && printf '{"state":"On"}' || printf '{"state":"Off"}' '';
              format = "{{ state }}";
              icon-name = "object-rotate-right-symbolic";
              icon-color = "fg-default";
              label-color = "fg-default";
            }
            {
              id = "storage";
              interval-ms = 10000;

              # eMMC (mmcblk1) has no temperature sensor
              command = "df -h / | awk 'NR==2{print $5}' ";
              format = "{{ output }}";
              icon-name = "drive-harddisk-symbolic";
              icon-color = "fg-default";
              label-color = "fg-default";
            }
            {
              # Performance mode (CPU + GPU performance governor).
              # Runs fydetab-perf using passwordless sudo (see shell/power.nix).
              id = "performance";
              interval-ms = 3000;
              command = ''[ "$(fydetab-perf status)" = on ] && printf '{"state":"On"}' || printf '{"state":"Off"}' '';
              left-click = ''
                if [ "$(fydetab-perf status)" = on ]; then
                  sudo -n fydetab-perf off
                  notify-send -a wayle -u low -t 2500 "Performance" "Performance mode disabling..."
                else
                  sudo -n fydetab-perf on
                  notify-send -a wayle -u low -t 2500 "Performance" "Performance mode enabling..."
                fi
              '';
              on-action = ''[ "$(fydetab-perf status)" = on ] && printf '{"state":"On"}' || printf '{"state":"Off"}' '';
              format = "{{ state }}";
              icon-name = "media-seek-forward-symbolic";
              icon-color = "fg-default";
              label-color = "fg-default";
            }
            {
              id = "tablet-mode";
              interval-ms = 3000;
              command = ''[ -f /run/tablet-mode/manual-off ] && printf '{"state":"Off"}' || printf '{"state":"On"}' '';
              left-click = ''
                if [ -f /run/tablet-mode/manual-off ]; then
                  rm -f /run/tablet-mode/manual-off
                  notify-send -a wayle -u low -t 2500 "Tablet mode" "OSK enabling..."
                else
                  touch /run/tablet-mode/manual-off
                  notify-send -a wayle -u low -t 2500 "Tablet mode" "OSK disabling..."
                fi
              '';
              on-action = ''[ -f /run/tablet-mode/manual-off ] && printf '{"state":"Off"}' || printf '{"state":"On"}' '';
              format = "{{ state }}";
              icon-name = "input-keyboard-symbolic";
              icon-color = "fg-default";
              label-color = "fg-default";
            }
          ];
        };

        styling = {
          rounding = "none";
          scale = 1.0;

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

    # The nixpkgs wayle module starts wayle.service on graphical-session.target,
    # which can start before the compositor's wayland-0 socket is inited / exists
    # (e.g. when the user systemd manager persists across a greetd restart).
    # Wayle then latches onto a stale socket and renders nothing. Override the
    # unit to wait until the compositor socket is ready.
    systemd.user.services.wayle = {
      Unit = {
        After = lib.mkForce [ "graphical-session.target" ];
        Requires = lib.mkForce [ "graphical-session.target" ];
      };
      Service = {
        ExecStartPre = (
          pkgs.writeShellScript "wayle-wait-socket" ''
            socket="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/''${WAYLAND_DISPLAY:-wayland-0}"
            for _ in $(seq 1 200); do
              if [ -S "$socket" ]; then
                # Socket file exists; give the compositor a bit to start
                # listening before wayle connects.
                sleep 0.2
                exit 0
              fi
              sleep 0.1
            done
            echo "wayle: wayland socket $socket not available after 20s" >&2
            exit 1
          ''
        );
      };
    };
  };
}
