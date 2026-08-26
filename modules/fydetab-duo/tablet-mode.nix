{
  config,
  lib,
  pkgs,
  nixpkgs-unstable,
  ...
}:
let
  cfg = config.hardware.fydetabduo.tabletMode;
  pkgsUnstable = import nixpkgs-unstable { system = pkgs.stdenv.hostPlatform.system; };

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

  # Uses mobintl layout in portrait, deskintl in landscape when built.
  monitorScript = pkgs.writeShellScript "tablet-mode-monitor" ''
    WVKBD="${pkgsUnstable.wvkbd}/bin/wvkbd-mobintl"
    INOTIFYWAIT="${pkgs.inotify-tools}/bin/inotifywait"
    KILLALL="${pkgs.procps}/bin/killall"
    PGREP="${pkgs.procps}/bin/pgrep"
    STATE_FILE="${stateFile}"

    # Initialise state file on first run
    if [ ! -f "$STATE_FILE" ]; then
      if grep -q "Fydetab Duo USB Keyboard" /proc/bus/input/devices 2>/dev/null; then
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
      else
        if ! $PGREP -x wvkbd-mobintl >/dev/null 2>&1; then
          $WVKBD --hidden --auto -l mobintl &
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

      Uses the mobintl layout in portrait and deskintl in landscape.
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
        ExecStop = "${pkgs.procps}/bin/killall -USR1 wvkbd-mobintl || true";
        Restart = "on-failure";
        RestartSec = 10;
      };
    };
  };
}
