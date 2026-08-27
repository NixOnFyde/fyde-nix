#!/bin/bash
set -u

output_log_file="/boot/fydetab-debug.txt"

# Collect diagnostic telemetry and dump to boot partition
{
  echo "=# fydetab debug dump $(date -Is)"
  uname -a

  echo
  echo "=# systemctl --failed"
  systemctl --failed --no-pager || true

  monitored_units=(
    greetd
    dbus-broker
    dbus.socket
    nscd
    sshd
    sshd-keygen
    logrotate-checkconf
    growpart
    systemd-growfs-root
    register-nix-paths
    fydetab-bluetooth
    NetworkManager
    ModemManager
    accounts-daemon
    fydetab-opengl-link
  )

  for unit_name in "${monitored_units[@]}"; do
    echo
    echo "=# status $unit_name"
    systemctl status "$unit_name" --no-pager -l || true
  done

  echo
  echo "=# root mount options"
  findmnt -no SOURCE,FSTYPE,OPTIONS / || true
  findmnt -no OPTIONS /nix/store || true

  echo
  echo "=# runtime dirs"
  ls -la /var/lib/regreet /var/log/regreet /run/dbus /run/greetd /run/user 2>&1 || true

  echo
  echo "=# regreet log"
  cat /var/log/regreet/*.log 2>&1 || true
} >"$output_log_file" 2>&1
