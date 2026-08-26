{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.hardware.fydetabduo.tabletMode;
  pkgsUnstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.hostPlatform.system; };

  stateDir = "/run/tablet-mode";
  stateFile = "${stateDir}/keyboard-state";

  udevHelper = pkgs.writeShellScript "tablet-mode-udev" ''
    STATE_FILE="${stateFile}"
    mkdir -p "${stateDir}"

    if [ "$1" = "add" ]; then
      echo "attached" > "$STATE_FILE"
    elif [ "$1" = "remove" ]; then
      # Only transition from attached to detached (avoids false positives
      # from unrelated input device removals).
      if [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "attached" ]; then
        echo "detached" > "$STATE_FILE"
      fi
    fi
  '';

  # Uses 'full' layout in portrait, 'landscape' in landscape (wvkbd 0.20).
  monitorScript = pkgs.writeShellScript "tablet-mode-monitor" ''
    WVKBD="${pkgsUnstable.wvkbd}/bin/wvkbd-mobintl"
    INOTIFYWAIT="${pkgs.inotify-tools}/bin/inotifywait"
    KILLALL="${pkgs.procps}/bin/killall"
    PGREP="${pkgs.procps}/bin/pgrep"
    STATE_FILE="${stateFile}"

    cleanup() { $KILLALL -USR1 wvkbd-mobintl 2>/dev/null || true; exit 0; }
    trap cleanup TERM

    # Initialise state file on first run
    if [ ! -f "$STATE_FILE" ]; then
      if [ -d /sys/bus/usb/devices/*/idVendor ] && grep -qr "05ac" /sys/bus/usb/devices/*/idVendor 2>/dev/null; then
        echo "attached" > "$STATE_FILE"
      else
        echo "detached" > "$STATE_FILE"
      fi
    fi

    act() {
      local state
      state=$(cat "$STATE_FILE")

      if [ "$state" = "attached" ]; then
        $KILLALL -USR1 wvkbd-mobintl 2>/dev/null || true   # hide
        rm -f /run/tablet-mode/manual-off                  # resume auto on next detach
      else
        if [ -f /run/tablet-mode/manual-off ]; then
          true  # manual override - don't start wvkbd
        elif ! $PGREP -x wvkbd-mobintl >/dev/null 2>&1; then
          $WVKBD --hidden --auto -H 500 -L 400 -l full --landscape-layers landscape &
        else
          $KILLALL -USR2 wvkbd-mobintl 2>/dev/null || true  # show
        fi
      fi
    }

    # React to initial state
    act

    # Watch for udev writes
    while true; do
      $INOTIFYWAIT -qq -e modify "$STATE_FILE"
      act
    done
  '';
in
{
  options.hardware.fydetabduo.tabletMode = {
    enable = lib.mkEnableOption ''
      Tablet mode: automatically show an on-screen keyboard (wvkbd) when the
      pogo-pin USB keyboard is detached, and hide it when re-attached.

      Uses the full layout in portrait and landscape layout in landscape.
      wvkbd auto-shows when a text field gains focus via zwp_text_input_v3.

      Works under any wlroots compositor (labwc, sway, river, niri).
    '';
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgsUnstable.wvkbd
      pkgs.inotify-tools
    ];

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0777 root root -"
    ];

    # Keyboard attach/detach -> write state file
    services.udev.extraRules = ''
      ACTION=="add",    SUBSYSTEM=="input", ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="8502", RUN+="${udevHelper} add"
      ACTION=="remove", SUBSYSTEM=="input", KERNEL=="event*",                                     RUN+="${udevHelper} remove"
    '';

    # User service: watches state file, and manages wvkbd lifecycle
    systemd.user.services.tablet-mode-monitor = {
      description = "Tablet mode monitor – manages OSK based on keyboard state";
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${monitorScript}";
        Restart = "on-failure";
        RestartSec = 10;
      };
    };
  };
}
