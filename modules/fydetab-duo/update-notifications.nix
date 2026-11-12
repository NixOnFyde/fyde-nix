{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo.updateNotifications;

  # Where the last check is cached, per user. The shell hook only reads this
  # file (a couple of ms), so opening a terminal never touches the network.
  cacheDirExpr = ''"''${XDG_CACHE_HOME:-$HOME/.cache}/fyde-nix"'';

  checkScript = pkgs.writeShellApplication {
    name = "fydetab-update-check";
    runtimeInputs = with pkgs; [
      coreutils
      git
      gnugrep
      gnused
      jq
      libnotify
    ];
    text = ''
      set -eu

      # No GitHub API calls here: `git ls-remote` is one unauthenticated
      # request and is not subject to the API rate limit. `nix flake
      # metadata` (used by fydetab-update itself) is, which is why this
      # check deliberately avoids it.
      export GIT_TERMINAL_PROMPT=0
      REPO="https://github.com/NixOnFyde/fyde-nix"
      FLAKE="github:NixOnFyde/fyde-nix"
      NIXOS_DIR="''${FYDETAB_NIXOS_DIR:-/etc/nixos}"
      CACHE_DIR=${cacheDirExpr}
      STATUS="$CACHE_DIR/update-status"
      NOTIFIED="$CACHE_DIR/last-notified"

      [ -r "$NIXOS_DIR/flake.nix" ] || exit 0
      [ -r "$NIXOS_DIR/flake.lock" ] || exit 0

      mkdir -p "$CACHE_DIR"

      tag="$(timeout 30 git ls-remote --tags --refs "$REPO" 'refs/tags/v*' 2>/dev/null \
        | sed -n 's|.*refs/tags/\(v[^ ^{}]*\)$|\1|p' \
        | sort -V \
        | tail -n 1)" || true
      [ -n "''${tag:-}" ] || exit 0

      # Annotated tags need the peeled (^{}) ref for the commit id.
      rev="$(timeout 30 git ls-remote "$REPO" "refs/tags/$tag^{}" 2>/dev/null | cut -f1)" || true
      [ -n "''${rev:-}" ] || rev="$(timeout 30 git ls-remote "$REPO" "refs/tags/$tag" 2>/dev/null | cut -f1)" || true
      [ -n "''${rev:-}" ] || exit 0

      cur_rev="$(jq -r '.nodes[]
        | select(.locked.owner? == "NixOnFyde" and .locked.repo? == "fyde-nix")
        | .locked.rev // empty' "$NIXOS_DIR/flake.lock" 2>/dev/null | head -n 1)" || true
      cur_tag="$(sed -n 's|.*NixOnFyde/fyde-nix/v\([0-9A-Za-z._-]*\).*|\1|p' \
        "$NIXOS_DIR/flake.nix" 2>/dev/null | head -n 1)" || true

      available=0
      if [ -n "$cur_tag" ]; then
        if [ "v$cur_tag" = "$tag" ]; then
          # Same tag, different commit: the tag was rebuilt (hotfix).
          [ -n "$cur_rev" ] && [ "$cur_rev" != "$rev" ] && available=1
        else
          # Only nag when the latest tag sorts above the pinned one.
          newest="$(printf '%s\n%s\n' "v$cur_tag" "$tag" | sort -V | tail -n 1)"
          [ "$newest" = "$tag" ] && available=1
        fi
      elif [ -n "$cur_rev" ] && [ "$cur_rev" != "$rev" ]; then
        # Tracking a branch or plain `github:NixOnFyde/fyde-nix`.
        available=1
      fi

      tmp="$(mktemp "$STATUS.XXXXXX")"
      {
        printf 'latest_tag=%s\n' "$tag"
        printf 'latest_rev=%s\n' "$rev"
        printf 'current_tag=%s\n' "$cur_tag"
        printf 'current_rev=%s\n' "$cur_rev"
        printf 'available=%s\n' "$available"
        printf 'checked=%s\n' "$(date +%s)"
      } > "$tmp"
      chmod 0644 "$tmp"
      mv -fT "$tmp" "$STATUS"

      # Desktop notification: once per release (not every six hours).
      if [ "''${FYDETAB_NOTIFY:-1}" = 1 ] && [ "$available" = 1 ] \
        && [ "$(cat "$NOTIFIED" 2>/dev/null || true)" != "$tag:$rev" ]; then
        if [ "$tag" = "v$cur_tag" ]; then
          summary="fyde-nix $tag hotfix available"
          body="Same tag, new build. Update to $rev."
        else
          summary="fyde-nix $tag available"
          body="You are on ''${cur_tag:+v$cur_tag}''${cur_tag:-''${cur_rev:-an unknown revision}}."
        fi
        body="$body

sudo nix run $FLAKE/$tag#fydetab-update"
        if notify-send -a fyde-nix -i system-software-update "$summary" "$body" 2>/dev/null; then
          printf '%s\n' "$tag:$rev" > "$NOTIFIED"
        fi
      fi
    '';
  };

  hintScript = pkgs.writeShellApplication {
    name = "fydetab-update-hint";
    runtimeInputs = with pkgs; [
      gnugrep
      gnused
    ];
    text = ''
      set -eu

      # Fast path: one local file, no network and no nix evaluation.
      STATUS=${cacheDirExpr}/update-status
      [ -r "$STATUS" ] || exit 0

      available="$(sed -n 's/^available=//p' "$STATUS")"
      [ "''${available:-0}" = 1 ] || exit 0

      tag="$(sed -n 's/^latest_tag=//p' "$STATUS")"
      cur="$(sed -n 's/^current_tag=//p' "$STATUS")"
      [ -n "''${tag:-}" ] || exit 0

      if [ "$tag" = "v$cur" ]; then
        msg="fyde-nix $tag has a hotfix available"
      elif [ -n "$cur" ]; then
        msg="fyde-nix $tag is available (you are on v$cur)"
      else
        msg="fyde-nix $tag is available"
      fi

      if [ -t 1 ]; then
        printf '\033[1;33m%s\033[0m\n' "$msg"
        printf '  Update: sudo nix run github:NixOnFyde/fyde-nix/%s#fydetab-update\n' "$tag"
      else
        printf '%s\n' "$msg"
      fi
    '';
  };
in
{
  options.hardware.fydetabduo.updateNotifications = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Tell the user when a newer fyde-nix release (or a rebuilt tag) is
        available. Enabled by default.

        The check runs in the background at most once every
        {option}`interval`; opening a terminal only reads a small cache file,
        so it never blocks on the network.
      '';
    };

    shellHint = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Print a one-line update hint when an interactive shell starts (bash
        and zsh). Reads the cached result only.
      '';
    };

    desktopNotification = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Also send a desktop notification (via notify-send) when a new release
        is found, at most once per release. Only works in a graphical session;
        failures are ignored.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "6h";
      description = "How often to check for updates (systemd time span).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      checkScript
      hintScript
    ];

    environment.interactiveShellInit = lib.mkIf cfg.shellHint ''
      ${hintScript}/bin/fydetab-update-hint
    '';

    systemd.user.services.fydetab-update-check = {
      description = "Check for a newer fyde-nix release";
      environment = lib.mkIf (!cfg.desktopNotification) {
        FYDETAB_NOTIFY = "0";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${checkScript}/bin/fydetab-update-check";
      };
    };

    systemd.user.timers.fydetab-update-check = {
      description = "Periodic fyde-nix release check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Late enough for the network to be up after boot, then every
        # `interval`. The shell hint does not depend on this timer.
        OnBootSec = "2min";
        OnUnitActiveSec = cfg.interval;
        RandomizedDelaySec = "5min";
        Persistent = true;
      };
    };
  };
}
