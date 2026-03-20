#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# CONFIGURATION — EDIT THESE VALUES
# ============================================================

DISK="/dev/nvme0n1"          # Target disk
HOSTNAME="archlinux-x1yoga"
USERNAME="alessap"
LANGUAGE="en_US.UTF-8"
SYSTEM_LOCALE="da_DK.UTF-8"
KEYMAP="dk-latin1"
TIMEZONE="Europe/Copenhagen"

# ============================================================
# PASSWORDS — PLAIN TEXT (HANDLE WITH CARE)
# ============================================================

LUKS_PASSWORD="LUKS_PASSWORD"
ROOT_PASSWORD="ROOT_PASSWORD"
USER_PASSWORD="USER_PASSWORD"

# ============================================================
# DERIVED
# ============================================================

EFI_PART="${DISK}p1"
ROOT_PART="${DISK}p2"
CRYPT_NAME="cryptroot"
MNT="/mnt"

log() { printf "\n==> %s\n" "$*"; }

# ============================================================
# HARD WARNING
# ============================================================

log "THIS SCRIPT WILL COMPLETELY WIPE ${DISK}."
read -rp "Type 'YES' to continue: " CONFIRM
[ "${CONFIRM}" = "YES" ] || { echo "Aborting."; exit 1; }

# ============================================================
# PRE-FLIGHT
# ============================================================

log "Checking UEFI mode..."
if ! [ -d /sys/firmware/efi/efivars ]; then
  echo "ERROR: System is not booted in UEFI mode."
  exit 1
fi

log "Enabling NTP..."
timedatectl set-ntp true || true

log "Cleaning previous mounts and mappings..."
mountpoint -q "${MNT}" && umount -R "${MNT}" || true
[ -e "/dev/mapper/${CRYPT_NAME}" ] && cryptsetup close "${CRYPT_NAME}" || true

# ============================================================
# DISK PARTITIONING (DESTRUCTIVE)
# ============================================================

log "Wiping ${DISK}..."
wipefs -af "${DISK}"
sgdisk -Zo "${DISK}"

log "Creating partitions..."
sgdisk -n1:0:+512M -t1:ef00 -c1:"EFI" "${DISK}"
sgdisk -n2:0:0     -t2:8300 -c2:"LUKS_BTRFS" "${DISK}"

partprobe "${DISK}"

# ============================================================
# LUKS + BTRFS
# ============================================================

log "Creating LUKS2 container..."
echo -n "${LUKS_PASSWORD}" | cryptsetup luksFormat --type luks2 "${ROOT_PART}" -
echo -n "${LUKS_PASSWORD}" | cryptsetup open "${ROOT_PART}" "${CRYPT_NAME}" -

log "Creating Btrfs filesystem..."
mkfs.btrfs -L archroot "/dev/mapper/${CRYPT_NAME}"

log "Creating subvolumes..."
mount "/dev/mapper/${CRYPT_NAME}" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@cache
btrfs subvolume create /mnt/@snapshots
umount /mnt

log "Mounting subvolumes..."
mount -o subvol=@,compress=zstd,noatime "/dev/mapper/${CRYPT_NAME}" "${MNT}"

mkdir -p ${MNT}/{boot,home,var/cache,var/log,.snapshots,var/cache/pacman/pkg}

mount -o subvol=@home,compress=zstd,noatime "/dev/mapper/${CRYPT_NAME}" "${MNT}/home"
mount -o subvol=@pkg,compress=zstd,noatime "/dev/mapper/${CRYPT_NAME}" "${MNT}/var/cache/pacman/pkg"
mount -o subvol=@log,compress=zstd,noatime "/dev/mapper/${CRYPT_NAME}" "${MNT}/var/log"
mount -o subvol=@cache,compress=zstd,noatime "/dev/mapper/${CRYPT_NAME}" "${MNT}/var/cache"
mount -o subvol=@snapshots,compress=zstd,noatime "/dev/mapper/${CRYPT_NAME}" "${MNT}/.snapshots"

log "Formatting EFI partition..."
mkfs.fat -F32 "${EFI_PART}"
mount "${EFI_PART}" "${MNT}/boot"

# ============================================================
# BASE SYSTEM
# ============================================================

log "Installing base system..."
pacstrap -K "${MNT}" \
  base base-devel linux linux-firmware \
  btrfs-progs grub efibootmgr \
  networkmanager sudo vim nano \
  intel-ucode amd-ucode \
  snapper snap-pac \
  grub-btrfs inotify-tools \
  tlp tlp-rdw acpi_call fwupd sof-firmware \
  iio-sensor-proxy \
  xf86-input-wacom libwacom \
  fprintd \
  plasma-meta kde-applications-meta \
  sddm sddm-kcm \
  konsole dolphin

log "Generating fstab..."
> "${MNT}/etc/fstab"
genfstab -U "${MNT}" >> "${MNT}/etc/fstab"

# ============================================================
# CHROOT CONFIG
# ============================================================

arch-chroot "${MNT}" /bin/bash <<EOF
set -euo pipefail

echo "==> Timezone..."
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

echo "==> Locales..."
sed -i "s/^#${LANGUAGE}/${LANGUAGE}/" /etc/locale.gen || echo "${LANGUAGE} UTF-8" >> /etc/locale.gen
sed -i "s/^#${SYSTEM_LOCALE}/${SYSTEM_LOCALE}/" /etc/locale.gen || echo "${SYSTEM_LOCALE} UTF-8" >> /etc/locale.gen
locale-gen

cat <<LOC >/etc/locale.conf
LANG=${LANGUAGE}
LC_TIME=${SYSTEM_LOCALE}
LC_NUMERIC=${SYSTEM_LOCALE}
LC_MONETARY=${SYSTEM_LOCALE}
LC_PAPER=${SYSTEM_LOCALE}
LC_MEASUREMENT=${SYSTEM_LOCALE}
LC_COLLATE=C
LOC

echo "==> Keymap..."
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

echo "==> Hostname..."
echo "${HOSTNAME}" > /etc/hostname
cat <<HST >/etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HST

echo "==> NetworkManager..."
systemctl enable NetworkManager

echo "==> mkinitcpio (LUKS + Btrfs)..."
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

echo "==> Root password (non-interactive)..."
echo "root:${ROOT_PASSWORD}" | chpasswd

echo "==> User ${USERNAME}..."
if id "${USERNAME}" >/dev/null 2>&1; then
  echo "User exists, updating password."
else
  useradd -m -G wheel -s /bin/bash "${USERNAME}"
fi
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

echo "==> Sudo for wheel..."
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "==> pacman.conf..."
sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sed -i 's/^DownloadUser/#DownloadUser/' /etc/pacman.conf

echo "==> GRUB with Btrfs snapshots..."
UUID=\$(blkid -s UUID -o value "${ROOT_PART}")
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\${UUID}:${CRYPT_NAME} root=/dev/mapper/${CRYPT_NAME} rootflags=subvol=@\"|" /etc/default/grub
grep -q '^GRUB_ENABLE_CRYPTODISK' /etc/default/grub || echo 'GRUB_ENABLE_CRYPTODISK=y' >> /etc/default/grub
grep -q '^GRUB_BTRFS_ENABLE' /etc/default/grub || echo 'GRUB_BTRFS_ENABLE=y' >> /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> grub-btrfsd..."
systemctl enable grub-btrfsd.service

echo "==> SDDM..."
systemctl enable sddm

echo "==> Snapper..."
if ! snapper list-configs | grep -q root; then
  snapper -c root create-config /
fi
if ! snapper list-configs | grep -q home; then
  snapper -c home create-config /home
fi

btrfs subvolume delete /.snapshots 2>/dev/null || true
mkdir -p /.snapshots
btrfs subvolume create /.snapshots 2>/dev/null || true

systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

echo "==> ThinkPad power + firmware..."
systemctl enable tlp
systemctl enable fwupd-refresh.timer

EOF

# ============================================================
# CLEANUP
# ============================================================

log "Unmounting..."
umount -R "${MNT}" || true
cryptsetup close "${CRYPT_NAME}" || true

log "Done. You can now reboot."
