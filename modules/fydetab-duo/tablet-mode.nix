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
  manualOff = "${stateDir}/manual-off";

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
    KILLALL="${pkgs.toybox}/bin/killall"
    PGREP="${pkgs.toybox}/bin/pgrep"
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

    show_wvkbd() {
      if ! $PGREP -x wvkbd-mobintl >/dev/null 2>&1; then
        $WVKBD --hidden --auto -H 500 -L 400 -l full --landscape-layers landscape &
      else
        $KILLALL -USR2 wvkbd-mobintl 2>/dev/null || true
      fi
    }

    kill_wvkbd() {
      $KILLALL -9 wvkbd-mobintl 2>/dev/null || true
    }

    # Track last state to avoid reacting to our own flag writes.
    last_kb=""
    last_flag=""

    act() {
      kb=$(cat "$STATE_FILE" 2>/dev/null)
      flag_exists="false"
      [ -f "${manualOff}" ] && flag_exists="true"

      # Skip if nothing changed
      [ "$kb" = "$last_kb" ] && [ "$flag_exists" = "$last_flag" ] && return

      if [ "$kb" != "$last_kb" ]; then
        # Keyboard state changed -> keyboard wins
        last_kb="$kb"

        if [ "$kb" = "attached" ]; then
          kill_wvkbd
          touch "${manualOff}"
        else
          rm -f "${manualOff}"
          show_wvkbd
        fi
      else
        # Flag changed by wayle toggle -> toggle wins
        if [ "$flag_exists" = "true" ]; then
          kill_wvkbd
        else
          show_wvkbd
        fi
      fi
      last_flag="$( [ -f "${manualOff}" ] && echo true || echo false )"
    }

    # React to initial state
    act

    # Watch keyboard-state (udev writes) and manual-off (wayle toggle).
    # inotifywait on the directory will catch creates/deletes of manual-off
    # as well as writes to keyboard-state.
    while true; do
      $INOTIFYWAIT -qq -e modify,create,delete "${stateDir}"
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

    # The remove rule uses ENV{DEVPATH}=="*05AC*" to match only the Apple
    # keyboard (vendor ID 05ac) and ignore unrelated input device removals
    # that occur during shutdown/rebuild (touchscreen, stylus, lid switch, etc.).
    # DEVPATH is set by the kernel and persists through remove events, unlike ATTRS{}
    # which goes through sysfs that may be partially torn down.
    services.udev.extraRules = ''
      ACTION=="add",    SUBSYSTEM=="input", ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="8502", RUN+="${udevHelper} add"
      ACTION=="remove", SUBSYSTEM=="input", KERNEL=="event*", ENV{DEVPATH}=="*05AC*",          RUN+="${udevHelper} remove"
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
