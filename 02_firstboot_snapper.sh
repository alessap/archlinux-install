#!/usr/bin/env bash
set -euo pipefail

USER_NAME="alessap"

echo "==> Ensuring /.snapshots is a proper Btrfs subvolume..."
if mountpoint -q /.snapshots; then
    echo "Unmounting existing .snapshots mount..."
    sudo umount /.snapshots || true
fi

# Prefer checking with `btrfs subvolume show` which succeeds only for subvolumes.
if sudo btrfs subvolume show /.snapshots >/dev/null 2>&1; then
    echo "Subvolume /.snapshots already exists."
else
    if [ -e /.snapshots ]; then
        # Backup any existing non-subvolume path to avoid 'File exists' errors
        TS=$(date +%s)
        BACKUP="/.snapshots.bak.$TS"
        echo "Found existing path /.snapshots that is not a btrfs subvolume. Moving to $BACKUP"
        sudo mv /.snapshots "$BACKUP" || { echo "Failed to move existing /.snapshots. Aborting."; exit 1; }
    fi
    echo "Creating /.snapshots subvolume..."
    sudo btrfs subvolume create /.snapshots
fi

sudo chmod 750 /.snapshots

echo "==> Creating Snapper configs if missing..."
if ! sudo snapper list-configs | grep -q root; then
    sudo snapper -c root create-config /
fi

if ! sudo snapper list-configs | grep -q home; then
    sudo snapper -c home create-config /home
fi

echo "==> Setting Snapper permissions..."
sudo snapper -c root set-config ALLOW_USERS="${USER_NAME}"
sudo snapper -c home set-config ALLOW_USERS="${USER_NAME}"

echo "==> Fixing ACLs for user access..."
sudo setfacl -m u:${USER_NAME}:rwx /.snapshots

echo "==> Enabling Snapper timers..."
sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer

echo "==> Ensuring grub-btrfs is active..."
sudo systemctl enable --now grub-btrfsd.service

echo "==> Ensuring pacman hooks exist..."
if [ ! -f /etc/pacman.d/hooks/snap-pac.conf ]; then
    echo "Installing snap-pac pacman hook..."
    sudo mkdir -p /etc/pacman.d/hooks
    sudo tee /etc/pacman.d/hooks/snap-pac.conf >/dev/null <<EOF
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Package
Target = *

[Action]
Description = Creating pre/post snapshots for pacman transactions...
When = PreTransaction
Exec = /usr/bin/snap-pac pre
When = PostTransaction
Exec = /usr/bin/snap-pac post
EOF
fi

echo "==> Regenerating GRUB config..."
sudo grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Creating a test snapshot..."
sudo snapper -c root create --description "initial-test-snapshot"

echo "==> Done. Snapper is fully configured."
