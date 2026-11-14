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
        pkgs.plymouth
        pkgs.systemd
      ]
    }"

    set -u

    timeout=${toString cfg.timeout}
    maxgens=${toString cfg.maxGenerations}
    rotation=${toString cfg.rotation}

    # `fydetab.bootmenu.timeout=N` on the kernel command line overrides the
    # configured window; useful for debugging without rebuilding.
    for arg in $(cat /proc/cmdline); do
      case "$arg" in
        fydetab.bootmenu.timeout=*) timeout=''${arg#*=} ;;
      esac
    done
    case "$timeout" in
      *[!0-9]*|"") timeout=${toString cfg.timeout} ;;
    esac

    tty=/dev/tty1
    echo "fydetab-boot-menu: starting (tty $tty)" >&2

    # Initrd journal messages can be lost when kexec transfers control or
    # resets the tablet. Keep a small trace on the mounted host filesystem so
    # the next boot can show which stage the handoff reached.
    handoff_log=/sysroot/var/log/fydetab-boot-menu-kexec.log
    handoff_trace() {
      if ! printf '%s boot=%s %s\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)" \
        "$*" >> "$handoff_log" 2>/dev/null; then
        echo "fydetab-boot-menu: could not write persistent handoff trace" >&2
        return 0
      fi
      sync -f "$handoff_log" 2>/dev/null || sync
    }

    # This initrd may have been started by the picker via kexec; in that case
    # show the chosen generation, not the menu again.
    case " $(cat /proc/cmdline) " in
      *" fydetab.bootmenu=skip "*)
        echo "fydetab-boot-menu: started by kexec, skipping" >&2
        handoff_trace "boot-menu skip-marker=present"
        exit 0
        ;;
    esac
    handoff_trace "boot-menu skip-marker=absent; opening picker"

    # Plymouth owns the display through DRM, so it has to go away for the
    # duration of the menu; the menu itself takes DRM master and scans out its
    # own buffer. Start Plymouth again for the normal boot path. (On the kexec
    # path the next kernel starts its own splash.)
    plymouth_running=""
    if [ -e /run/plymouth/pid ]; then
      if plymouth --quit >/dev/null 2>&1; then
        plymouth_running=1
        # Give the daemon a moment to drop DRM master so fbcon takes over.
        sleep 0.3
      else
        echo "fydetab-boot-menu: could not stop Plymouth; the menu may be hidden" >&2
      fi
    fi

    resume_plymouth() {
      if [ -n "$plymouth_running" ]; then
        systemctl restart plymouth-start.service >/dev/null 2>&1 || true
      fi
    }
    trap resume_plymouth EXIT

    # We run in the initrd: the real root (which holds /nix) is mounted at
    # /sysroot. The profile links are absolute symlinks into /nix/store, which
    # would resolve inside the initrd's own (unrelated) /nix, so read the link
    # targets as strings and prepend /sysroot for file access. The paths
    # handed to the kernel (init=) stay in host form.
    root=/sysroot
    profiles=$root/nix/var/nix/profiles

    # Resolve a symlink chain inside the host root.  Generation closures link
    # to /nix/store/... with absolute paths, which would resolve against the
    # initrd's own (unrelated) /nix, so prefix absolute targets with /sysroot.
    host_path() {
      local p=$1 t
      while [ -L "$p" ]; do
        t=$(readlink "$p" 2>/dev/null) || return 1
        case "$t" in
          /*) p=$root$t ;;
          *) p=$(dirname "$p")/$t ;;
        esac
      done
      printf '%s\n' "$p"
    }

    shopt -s nullglob
    links=($profiles/system-*-link)
    if [ "''${#links[@]}" -eq 0 ]; then
      echo "fydetab-boot-menu: no generations found" >&2
      exit 0
    fi

    default_num="?"
    if [ -L "$profiles/system" ]; then
      target=$(readlink "$profiles/system" 2>/dev/null || true)
      default_num=''${target##*/}
      default_num=''${default_num#system-}
      default_num=''${default_num%-link}
      case "$default_num" in
        "" | *[!0-9]*) default_num="?" ;;
      esac
    fi

    gens=()
    nums=()
    dates=()
    sel=0

    for link in $(printf '%s\n' "''${links[@]}" | sort -Vr); do
      num=''${link##*/system-}
      num=''${num%-link}

      # The profile link points at /nix/store/<hash>-nixos-system-…; skip
      # generations whose kernel assets were garbage-collected.
      store=$(readlink "$link" 2>/dev/null || true)
      case "$store" in
        /*) ;;
        "") continue ;;
        *) store=$(dirname "$link")/$store ;;
      esac
      g=$root$store
      if [ ! -x "$(host_path "$g/init")" ] || [ ! -L "$g/kernel" ] || [ ! -L "$g/initrd" ]; then
        continue
      fi

      # stat the profile link itself (not its target) for generation time
      ts=$(stat -c %Y "$link" 2>/dev/null || echo 0)
      when=$(date -d "@$ts" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "?")

      if [ "$num" = "$default_num" ]; then
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
    if [ "$timeout" -le 0 ] || [ "$n" -eq 0 ]; then
      exit 0
    fi

    has_spec=0
    for g in "''${gens[@]}"; do
      [ -d "$g/specialisation" ] || continue
      for s in "$g"/specialisation/*; do
        sp=$(host_path "$s") || continue
        if [ -x "$sp/init" ]; then
          has_spec=1
          break
        fi
      done
    done
    # A single generation without specialisations has nothing to choose.
    if [ "$n" -le 1 ] && [ "$has_spec" -eq 0 ]; then
      exit 0
    fi

    # Hand the generations (and their specialisations) to the menu.  It owns
    # the VT while it runs and prints "-1" or "<generation>[/<name>]".
    lines=""
    i=0
    while [ "$i" -lt "$n" ]; do
      flag=0
      [ "''${nums[$i]}" = "$default_num" ] && flag=1
      lines="$lines"'G|'"''${nums[$i]}"'|'"''${dates[$i]}"'|'"$flag"$'\n'
      g="''${gens[$i]}"
      if [ -d "$g/specialisation" ]; then
        for s in "$g"/specialisation/*; do
          sp=$(host_path "$s") || continue
          [ -x "$sp/init" ] || continue
          lines="$lines"'S|'"''${s##*/}"$'\n'
        done
      fi
      i=$((i + 1))
    done

    choice=$(
      printf '%s' "$lines" | ${pkgs.fydetab-boot-menu-ui}/bin/fydetab-boot-menu-ui \
        --timeout "$timeout" \
        --rotation "$rotation" \
        --tty "$tty"
    )
    rc=$?
    echo "fydetab-boot-menu: ui exit $rc, choice '$choice'" >&2
    handoff_trace "picker-result ui-exit=$rc choice='$choice'"
    if [ "$rc" -ne 0 ]; then
      choice=-1
    fi

    case "$choice" in
      "" | -*) exit 0 ;;
      *[!0-9/-]*) exit 0 ;;
    esac

    gen=''${choice%%/*}
    spec=""
    case "$choice" in
      */*) spec=''${choice#*/} ;;
    esac

    gi=-1
    i=0
    while [ "$i" -lt "$n" ]; do
      [ "''${nums[$i]}" = "$gen" ] && gi=$i
      i=$((i + 1))
    done
    [ "$gi" -lt 0 ] && exit 0

    g="''${gens[$gi]}"
    label=$gen
    if [ -n "$spec" ]; then
      g=$(host_path "$g/specialisation/$spec") || exit 0
      label="$gen $spec"
      [ -x "$(host_path "$g/init")" ] || exit 0
    fi

    # kexec reads these files through /sysroot, but the new kernel needs
    # the host path for init=.
    host=''${g#"$root"}
    printf 'Starting generation %s...\n' "$label" > "$tty"

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
    new="''${new# } init=$host/init fydetab.bootmenu=skip systemd.mask=fydetab-boot-menu.service"

    kernel=$(host_path "$g/kernel") || kernel=$g/kernel
    initrd=$(host_path "$g/initrd") || initrd=$g/initrd
    dtbs=$(host_path "$g/dtbs") || dtbs=$g/dtbs

    handoff_trace "selected generation=$label kernel='$kernel' initrd='$initrd' dtb='$dtbs/rockchip/rk3588s-fydetab_duo.dtb'"

    handoff_trace "kexec-load starting generation=$label"
    err=$(kexec -s -l "$kernel" \
      --initrd="$initrd" \
      --dtb="$dtbs/rockchip/rk3588s-fydetab_duo.dtb" \
      --command-line="$new" 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then
      handoff_trace "kexec-load succeeded generation=$label"
      # rfkill_wlan_shutdown() powers the Wi-Fi card off during kexec's
      # device_shutdown.  The next kernel probes rk-pcie before wlan-platdata
      # can power the card back on, so the PCIe link never trains and the
      # tablet comes up without Wi-Fi.  Unbinding the platform driver keeps the
      # card powered: its remove path only frees the GPIOs (the pad keeps its
      # output level) and never calls rfkill_wlan_shutdown().
      handoff_trace "wlan-platdata unbind phase starting"
      if [ -d /sys/bus/platform/drivers/wlan-platdata ]; then
        wlan_devices=0
        for dev in /sys/bus/platform/drivers/wlan-platdata/*; do
          [ "''${dev##*/}" = module ] && continue
          [ -e "$dev/driver" ] || {
            handoff_trace "wlan-platdata device not bound path=''${dev##*/}"
            continue
          }
          wlan_devices=$((wlan_devices + 1))
          handoff_trace "wlan-platdata unbind starting device=''${dev##*/}"
          if printf '%s' "''${dev##*/}" \
              > /sys/bus/platform/drivers/wlan-platdata/unbind 2>/dev/null; then
            echo "fydetab-boot-menu: unbound wlan-platdata ''${dev##*/}" >&2
            handoff_trace "wlan-platdata unbound device=''${dev##*/}"
          else
            echo "fydetab-boot-menu: cannot unbind wlan-platdata ''${dev##*/}" >&2
            handoff_trace "wlan-platdata unbind-failed device=''${dev##*/}"
          fi
        done
        [ "$wlan_devices" -gt 0 ] || handoff_trace "wlan-platdata no bound devices"
      else
        echo "fydetab-boot-menu: wlan-platdata driver not present" >&2
        handoff_trace "wlan-platdata driver-not-present"
      fi

      handoff_trace "kexec-exec entering generation=$label"
      err=$(kexec -e 2>&1)
      rc=$?
      if [ "$rc" -eq 0 ]; then
        echo "fydetab-boot-menu: kexec -e returned successfully" >&2
        handoff_trace "kexec-exec returned-successfully generation=$label output='$err'"
      else
        echo "fydetab-boot-menu: kexec -e failed ($rc): $err" >&2
        handoff_trace "kexec-exec failed rc=$rc generation=$label output='$err'"
      fi
    else
      echo "fydetab-boot-menu: kexec load failed ($rc): $err" >&2
      handoff_trace "kexec-load failed rc=$rc generation=$label output='$err'"
    fi

    printf 'Could not start generation %s; continuing with the default.\n' \
      "$label" > "$tty"
    sleep 3
  '';

in
{
  options.hardware.fydetabduo.bootMenu = {
    enable =
      (lib.mkEnableOption ''
        a generation picker in the initrd. U-Boot still boots the normal
        kernel; before the switch to the real root a menu lists the installed
        NixOS generations and their specialisations, and picking one kexecs
        that entry's own kernel, initrd and DTB. The default entry boots
        exactly like before
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
        changing the boot path. The countdown pauses as soon as any key is
        pressed.
      '';
    };

    maxGenerations = lib.mkOption {
      type = lib.types.ints.between 2 9;
      default = 8;
      description = "How many generations to list (newest first), at most 9 so number keys can select them.";
    };

    rotation = lib.mkOption {
      type = lib.types.enum [
        90
        270
      ];
      default = 270;
      description = ''
        Rotation applied to the menu when the framebuffer is portrait
        (1600x2560). 270 matches the display transform used by the desktop;
        use 90 if the menu appears upside down.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.boot.initrd.systemd.enable;
        message = "hardware.fydetabduo.bootMenu requires boot.initrd.systemd.enable (the default in NixOS).";
      }
    ];

    # kexec's RPATH needs zlib/zstd, and bash/coreutils/kbd must exist inside
    # the initrd. The menu helper draws through DRM and reads evdev.
    boot.initrd.systemd.storePaths = [
      menu
      pkgs.fydetab-boot-menu-ui
      pkgs.bash
      pkgs.coreutils
      pkgs.kbd
      pkgs.kexec-tools
      pkgs.plymouth
      pkgs.zlib
      pkgs.zstd
    ];

    # The touchscreen is a module; load it in the initrd so the picker can be
    # used by touch as well as by the keyboard dock.
    boot.initrd.kernelModules = [ "himax_tp" ];

    boot.initrd.systemd.services.fydetab-boot-menu = {
      description = "FydeTab Duo generation picker";
      # Run during initrd.target, before initrd-cleanup starts the switch-root
      # transaction: udev is still running, so the keyboard and touchscreen
      # nodes are live, and ordering the picker before initrd-cleanup.service
      # keeps the isolate from tearing the menu down mid-countdown.
      wantedBy = [ "initrd.target" ];
      after = [ "sysroot.mount" ];
      before = [ "initrd-cleanup.service" "initrd-switch-root.service" ];

      # Default dependencies would order this after basic.target, which is
      # far too late: the whole point is to run before switch-root.
      unitConfig.DefaultDependencies = false;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardInput = "null";
        StandardOutput = "journal";
        StandardError = "journal";
        # The helper opens this VT itself and switches it to KD_GRAPHICS.
        TTYPath = "/dev/tty1";
        TTYReset = "no";
        TTYVHangup = "no";
        ExecStart = menu;
      };
    };
  };
}
