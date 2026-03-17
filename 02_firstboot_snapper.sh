#!/bin/bash

set -euo pipefail

# First-boot snapper setup. This script should be run on the installed system
# (e.g. on first boot as root). It requires systemd/DBus to be active.

if [ ! -S /run/dbus/system_bus_socket ]; then
    echo "System DBus socket not available; run this script after systemd is running"
    exit 1
fi

if ! command -v snapper >/dev/null 2>&1; then
    pacman -Sy --noconfirm snapper || true
fi

# Create root config if not present
if ! snapper -c root list >/dev/null 2>&1; then
    snapper -c root create-config / || true
fi

# Create home config if /home exists and config not present
if [ -d /home ] && ! snapper -c home list >/dev/null 2>&1; then
    snapper -c home create-config /home || true
fi

# Ensure timers enabled
systemctl enable snapper-timeline.timer || true
systemctl enable snapper-cleanup.timer || true

echo "Snapper first-boot configuration finished."

exit 0
