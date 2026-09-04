{
  lib,
  pkgs,
  config,
  ...
}:
let
  wallpaper = "/run/current-system/sw/share/backgrounds/fydetab-duo/wallpaper.jpg";
  weather = config.fydetabShell.wayle.weather;
  autoRotate = config.fydetabShell.wayle.autoRotate;
in
{
  options.fydetabShell.wayle.weather = {
    latitude = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Latitude for the wayle weather module, e.g. 51.5 for London.
        Left null, wayle falls back to its built-in default location.
      '';
    };
    longitude = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Longitude for the wayle weather module, e.g. -0.1 for London.
        Left null, wayle falls back to its built-in default location.
      '';
    };
  };

  options.fydetabShell.wayle.autoRotate = {
    statusCommand = lib.mkOption {
      type = lib.types.str;
      description = ''
        Shell command for the wayle auto-rotate bar module that reports the
        current state as JSON, e.g. '{"state":"On"}' when auto-rotation is on.
      '';
      default = ''systemctl --user is-active rot8 >/dev/null 2>&1 && printf '{"state":"On"}' || printf '{"state":"Off"}' '';
    };
    toggleCommand = lib.mkOption {
      type = lib.types.str;
      description = ''
        Shell command for the wayle auto-rotate bar module that starts/stops
        the auto-rotation daemon on click.
      '';
      default = ''
        if systemctl --user is-active rot8 >/dev/null 2>&1; then
          systemctl --user stop rot8
          notify-send -a wayle -u low -t 2500 "Auto-rotate" "Auto-rotate disabling..."
        else
          systemctl --user start rot8
          notify-send -a wayle -u low -t 2500 "Auto-rotate" "Auto-rotate enabling..."
        fi
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
                "clock"
                "custom-auto-rotate"
                "custom-tablet-mode"
                "systray"
              ];
              center = [
                "cpu"
                "ram"
                "custom-storage"
                "weather"
              ];
              right = [
                "volume"
                "microphone"
                "brightness"
                "network"
                "bluetooth"
                "battery"
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
            format = "%a %d %B %Y - %T";
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
            location = "${weather.latitude},${weather.longitude}";
          };

          custom = [
            {
              id = "auto-rotate";
              mode = "poll";
              interval-ms = 1000;
              command = autoRotate.statusCommand;
              left-click = autoRotate.toggleCommand;
              on-action = autoRotate.statusCommand;
              format = "{{ state }}";
              icon-name = "object-rotate-right-symbolic";
              icon-color = "fg-default";
              label-color = "fg-default";
            }
            {
              id = "storage";
              mode = "poll";
              interval-ms = 10000;

              # eMMC (mmcblk1) has no temperature sensor
              command = "df -h / | awk 'NR==2{print $5}' ";
              format = "{{ output }}";
              icon-name = "drive-harddisk-symbolic";
              icon-color = "fg-default";
              label-color = "fg-default";
            }
            {
              # Tablet mode: watch /run/tablet-mode/ for fs events.
              id = "tablet-mode";
              mode = "watch";
              restart-policy = "on-failure";
              command = pkgs.writeShellScript "wayle-tablet-watch" ''
                DIR="/run/tablet-mode"
                mkdir -p "$DIR"

                emit() {
                  if [ -f "$DIR/manual-off" ]; then
                    printf '{"state":"Off"}\n'
                  else
                    printf '{"state":"On"}\n'
                  fi
                }

                # Emit initial state
                emit

                # Watch for creates/deletes/modifies in the state directory
                ${pkgs.inotify-tools}/bin/inotifywait -m -e create,delete,modify "$DIR" 2>/dev/null | while IFS= read -r _; do
                  emit
                done
              '';
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
