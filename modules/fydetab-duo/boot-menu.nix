{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo.bootMenu;

  # Runs inside the systemd initrd, after the real root is mounted and before
  # the switch to it. U-Boot still boots `/boot.scr` as usual; this only gives
  # you a chance to pick a different NixOS generation, which is then started
  # with kexec() using that generation's own kernel, initrd and DTB.
  menu = pkgs.writeShellScript "fydetab-boot-menu" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.kbd
        pkgs.kexec-tools
      ]
    }"

    set -u

    timeout=${toString cfg.timeout}
    maxgens=${toString cfg.maxGenerations}

    # Plymouth owns the DRM device on tty1. Switch to an unused VT so the
    # plain framebuffer console is visible and the keyboard is routed to it.
    # Plymouth keeps running and resumes when we switch back.
    tty=/dev/tty1
    switched=""
    if [ -e /run/plymouth/pid ] && chvt 2 2>/dev/null; then
      tty=/dev/tty2
      switched=1
    fi

    finish() {
      if [ -n "$switched" ]; then
        chvt 1 2>/dev/null || true
      fi
    }
    trap finish EXIT

    shopt -s nullglob
    all=(/nix/var/nix/profiles/system-*-link)
    if [ "''${#all[@]}" -eq 0 ]; then
      exit 0
    fi

    default=$(readlink -f /nix/var/nix/profiles/system 2>/dev/null || true)
    default_num="?"
    if [ -n "$default" ]; then
      default_num=''${default##*/system-}
      default_num=''${default_num%-link}
      case "$default_num" in
        "" | *[!0-9]*) default_num="?" ;;
      esac
    fi

    gens=()
    nums=()
    dates=()
    sel=0

    for g in $(printf '%s\n' "''${all[@]}" | sort -Vr); do
      # Skip generations whose kernel assets were garbage-collected.
      if [ ! -x "$g/init" ] || [ ! -e "$g/kernel" ] || [ ! -e "$g/initrd" ]; then
        continue
      fi

      num=''${g##*/system-}
      num=''${num%-link}
      ts=$(stat -c %Y "$g" 2>/dev/null || echo 0)
      when=$(date -d "@$ts" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "?")

      if [ "$g" = "$default" ]; then
        sel=''${#gens[@]}
      fi

      gens+=("$g")
      nums+=("$num")
      dates+=("$when")

      if [ "''${#gens[@]}" -ge "$maxgens" ]; then
        break
      fi
    done

    n=''${#gens[@]}
    # Nothing to choose from (or the menu is disabled): boot straight away.
    if [ "$n" -le 1 ] || [ "$timeout" -le 0 ]; then
      exit 0
    fi

    left=$timeout

    draw() {
      {
        printf '\033[2J\033[H'
        printf 'FydeTab Duo boot menu\n\n'
        printf '  Up/Down or 1-%d to select, Enter to boot the highlighted one.\n' "$n"
        printf '  Press t for the default. Booting generation %s in %2ds...\n\n' "$default_num" "$left"
        i=0
        while [ "$i" -lt "$n" ]; do
          marker='  '
          [ "$i" -eq "$sel" ] && marker='> '
          note=""
          [ "''${gens[$i]}" = "$default" ] && note='  (default)'
          printf '%s[%d] gen %-3s  %s%s\n' "$marker" "$((i + 1))" "''${nums[$i]}" "''${dates[$i]}" "$note"
          i=$((i + 1))
        done
        printf '\n'
      } > "$tty"
    }

    while [ "$left" -gt 0 ]; do
      draw
      if read -rsn1 -t 1 key < "$tty"; then
        case "$key" in
          "")
            break
            ;;
          $'\e')
            read -rsn1 -t 0.1 k < "$tty" || k=""
            if [ "$k" = '[' ]; then
              read -rsn1 -t 0.1 k < "$tty" || k=""
            fi
            case "$k" in
              A) sel=$(((sel - 1 + n) % n)) ;;
              B) sel=$(((sel + 1) % n)) ;;
            esac
            ;;
          [1-9])
            idx=$((key - 1))
            [ "$idx" -lt "$n" ] && sel=$idx
            ;;
          j | J) sel=$(((sel + 1) % n)) ;;
          k | K) sel=$(((sel - 1 + n) % n)) ;;
          q | Q | t | T) left=0 ;;
        esac
        [ "$left" -gt 0 ] && left=$timeout
      fi
      left=$((left - 1))
    done

    # Timeout (or explicit "default") boots the current default generation.
    if [ "$left" -le 0 ] || [ "''${gens[$sel]}" = "$default" ]; then
      exit 0
    fi

    if [ "''${gens[$sel]}" != "$default" ]; then
      g=''${gens[$sel]}
      printf 'Starting generation %s...\n' "''${nums[$sel]}" > "$tty"

      # Reuse the current command line, only swapping the init= path. All
      # generations share the same root filesystem and kernel parameters.
      cmdline=$(cat /proc/cmdline)
      new=""
      for word in $cmdline; do
        case "$word" in
          init=*) ;;
          *) new="$new $word" ;;
        esac
      done
      new="''${new# } init=$g/init"

      if kexec -s -l "$g/kernel" \
        --initrd="$g/initrd" \
        --dtb="$g/dtbs/rockchip/rk3588s-fydetab_duo.dtb" \
        --command-line="$new" >/dev/null 2>&1; then
        kexec -e || true
      fi

      printf 'Could not start generation %s; continuing with the default.\n' \
        "''${nums[$sel]}" > "$tty"
      sleep 3
    fi
  '';

in
{
  options.hardware.fydetabduo.bootMenu = {
    enable =
      (lib.mkEnableOption ''
        a generation picker in the initrd. U-Boot still boots the normal
        kernel; before the switch to the real root a menu lists the installed
        NixOS generations, and picking one kexecs that generation's own kernel,
        initrd and DTB. The default entry boots exactly like before
      '')
      // {
        # Recovery matters more than five seconds of boot time; set
        # hardware.fydetabduo.bootMenu.enable = false or timeout = 0 to skip.
        default = true;
        defaultText = lib.literalExpression "true";
      };

    timeout = lib.mkOption {
      type = lib.types.ints.between 0 60;
      default = 5;
      description = ''
        Seconds to wait for a selection. 0 disables the menu without
        changing the boot path.
      '';
    };

    maxGenerations = lib.mkOption {
      type = lib.types.ints.between 2 9;
      default = 8;
      description = "How many generations to list (newest first), at most 9 so number keys can select them.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.boot.initrd.systemd.enable;
        message = "hardware.fydetabduo.bootMenu requires boot.initrd.systemd.enable (the default in NixOS).";
      }
    ];

    # The menu is a shell script; kexec's RPATH needs zlib/zstd, and bash,
    # coreutils and kbd must exist inside the initrd as well.
    boot.initrd.systemd.storePaths = [
      menu
      pkgs.bash
      pkgs.coreutils
      pkgs.kbd
      pkgs.kexec-tools
      pkgs.zlib
      pkgs.zstd
    ];

    boot.initrd.systemd.services.fydetab-boot-menu = {
      description = "FydeTab Duo generation picker";
      wantedBy = [ "initrd-switch-root.target" ];
      after = [ "sysroot.mount" ];
      before = [ "initrd-switch-root.service" ];

      # Default dependencies would order this after basic.target, which is
      # far too late: the whole point is to run before switch-root.
      unitConfig.DefaultDependencies = false;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # tty1 is the panel console (`console=tty1` is the last console=).
        StandardInput = "tty";
        StandardOutput = "tty";
        StandardError = "tty";
        TTYPath = "/dev/tty1";
        TTYReset = "yes";
        TTYVHangup = "no";
        ExecStart = menu;
      };
    };
  };
}
