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
  userStateDir = "$XDG_RUNTIME_DIR/tablet-mode";
  udevHelper = pkgs.writeShellScript "tablet-mode-udev" ''
    set -euo pipefail

    STATE_FILE="${stateFile}"

    write_state() {
      local value="$1"
      local tmp
      tmp=$(${pkgs.coreutils}/bin/mktemp "''${STATE_FILE}.XXXXXX")
      printf '%s\n' "$value" > "$tmp"
      ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
      ${pkgs.coreutils}/bin/mv -fT "$tmp" "$STATE_FILE"
    }

    if [ "$1" = "add" ]; then
      write_state attached
    elif [ "$1" = "remove" ]; then
      # Only transition from attached to detached (avoids false positives
      # from unrelated input device removals).
      if [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "attached" ]; then
        write_state detached
      fi
    fi
  '';

  # Uses 'full' layout in portrait, 'landscape' in landscape (wvkbd 0.20).
  monitorScript = pkgs.writeShellScript "tablet-mode-monitor" ''
    WVKBD="${pkgsUnstable.wvkbd}/bin/wvkbd-mobintl"
    INOTIFYWAIT="${pkgs.inotify-tools}/bin/inotifywait"
    KILLALL="${pkgs.toybox}/bin/killall"
    PGREP="${pkgs.toybox}/bin/pgrep"
    USER_STATE_DIR="${userStateDir}"
    MANUAL_OFF="$USER_STATE_DIR/manual-off"

    mkdir -p "$USER_STATE_DIR"

    cleanup() { $KILLALL -USR1 wvkbd-mobintl 2>/dev/null || true; exit 0; }
    trap cleanup TERM

    read_keyboard_state() {
      # Treat sysfs as authoritative, as udev emits one event per input node, so
      # a composite keyboard can remove one node while another remains bound.
      kb="detached"
      for device in /sys/bus/usb/devices/*; do
        [ -r "$device/idVendor" ] && [ -r "$device/idProduct" ] || continue
        if [ "$(cat "$device/idVendor")" = "05ac" ] &&
           [ "$(cat "$device/idProduct")" = "8502" ]; then
          kb="attached"
          break
        fi
      done
    }

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
      read_keyboard_state

      # Ignore brief USB disconnect/re-enumeration glitches. Once detached
      # stays stable, the OSK appears after 1.5 seconds; reattach hides it
      # immediately.
      if [ "$kb" = "detached" ] && [ "$last_kb" != "detached" ]; then
        ${pkgs.coreutils}/bin/sleep 1.5
        read_keyboard_state
      fi

      flag_exists="false"
      [ -f "$MANUAL_OFF" ] && flag_exists="true"

      # Skip if nothing changed
      [ "$kb" = "$last_kb" ] && [ "$flag_exists" = "$last_flag" ] && return

      if [ "$kb" != "$last_kb" ]; then
        # Keyboard state changed -> keyboard wins
        last_kb="$kb"

        if [ "$kb" = "attached" ]; then
          kill_wvkbd
          touch "$MANUAL_OFF"
        else
          rm -f "$MANUAL_OFF"
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
      last_flag="$( [ -f "$MANUAL_OFF" ] && echo true || echo false )"
    }

    # React to initial state
    act

    # Watch root-owned keyboard state and this user's manual toggle separately.
    while true; do
      $INOTIFYWAIT -m -q -e modify,create,delete,moved_to,moved_from "${stateDir}" "$USER_STATE_DIR" |
        while IFS= read -r _event; do
          act
        done || true
      ${pkgs.coreutils}/bin/sleep 1
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
      "d ${stateDir} 0755 root root -"
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
