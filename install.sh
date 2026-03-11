#!/bin/bash

# tested on a ThinkPad X260

set -exo pipefail

# Configuration

# Default values
DEFAULT_DISK="/dev/sdb"
DEFAULT_COUNTRY="Denmark"
DEFAULT_KEYMAP="dk-latin1"
DEFAULT_HOST_NAME="archlinux"
DEFAULT_USER="user"
DEFAULT_TIMEZONE="Europe/Copenhagen"
DESKTOP="kde"

if [ -z "$DISK" ]; then
    read -e -i "$DEFAULT_DISK" -p "Enter the target disk device (e.g., /dev/sdb): " DISK
    DISK=${DISK:-$DEFAULT_DISK}
fi
if [ -z "$COUNTRY" ]; then
    read -e -i "$DEFAULT_COUNTRY" -p "Enter your country for mirrorlist (e.g., Denmark): " COUNTRY
    COUNTRY=${COUNTRY:-$DEFAULT_COUNTRY}
fi
if [ -z "$KEYMAP" ]; then
    read -e -i "$DEFAULT_KEYMAP" -p "Enter your keymap (e.g., dk-latin1): " KEYMAP
    KEYMAP=${KEYMAP:-$DEFAULT_KEYMAP}
fi
if [ -z "$HOST_NAME" ]; then
    read -e -i "$DEFAULT_HOST_NAME" -p "Enter hostname: " HOST_NAME
    HOST_NAME=${HOST_NAME:-$DEFAULT_HOST_NAME}
fi
if [ -z "$USER" ]; then
    read -e -i "$DEFAULT_USER" -p "Enter username: " USER
    USER=${USER:-$DEFAULT_USER}
fi
if [ -z "$TIMEZONE" ]; then
    read -e -i "$DEFAULT_TIMEZONE" -p "Enter timezone (e.g., Europe/Copenhagen): " TIMEZONE
    TIMEZONE=${TIMEZONE:-$DEFAULT_TIMEZONE}
fi
if [ -z "$PASSWD" ]; then
    read -s -p "Enter password for encryption and user accounts: " PASSWD
    echo
fi

# Main setup
setup() {
    system_clock
    create_mirrorlist
    zap_disk
    partition_disk
    encrypt_main_partition
    create_volumes
    format_partitions
    mount_file_system
    install_base
    chroot
}

# Chroot setup
chrootsetup() {
    timezone
    localization
    network_configuration
    set_root_passwd
    install_packages
    initramfs
    bootloader
    add_user
    video_driver
    install_desktop
    enable_services
    exit 0
}

chrootsetupbootstrap() {
    timezone
    localization
    network_configuration
    set_root_passwd
    install_packages
    add_user
    video_driver
    install_desktop
    enable_services
    exit 0
}

# Update system clock
system_clock() {
    echo "Update system clock"
    timedatectl set-ntp true
}

# Create mirrorlist
create_mirrorlist() {
    echo "Creating mirrorlist"
    pacman -Syy --noconfirm python3 reflector
    reflector -c $COUNTRY -a 6 --sort rate --save /etc/pacman.d/mirrorlist
    pacman -Syyy
}

# Zap disk
zap_disk() {
    echo "Zapping disk ${DISK}"
    read -p "WARNING: This will erase all data on $DISK. Type YES to continue: " confirm
    if [[ "$confirm" != "YES" ]]; then
        echo "Aborting disk zap."
        exit 1
    fi
    sgdisk --zap-all $DISK || { echo "Failed to zap disk $DISK"; exit 1; }
}

# Parition disk
partition_disk() {
    echo "Partion disk ${DISK}"
    sgdisk -n 0:0:+260M -t 0:ef00 $DISK || { echo "Failed to create EFI partition on $DISK"; exit 1; }
    sgdisk -n 0:0:0 -t 0:8e00 $DISK || { echo "Failed to create LVM partition on $DISK"; exit 1; }

    UEFI_PARTITION=$(fdisk -l $DISK | grep 'EFI' | awk '{print $1}')
    MAIN_PARTITION=$(fdisk -l $DISK | grep 'LVM' | awk '{print $1}')
    if [ -z "$UEFI_PARTITION" ] || [ -z "$MAIN_PARTITION" ]; then
        echo "Partitioning failed. Could not find UEFI or LVM partition."
        exit 1
    fi
}


# Encrypt main partition
encrypt_main_partition() {
    echo "Encrypt main partition"
    echo -n "${PASSWD}" | cryptsetup luksFormat $MAIN_PARTITION - || { echo "LUKS format failed"; exit 1; }
    echo -n "${PASSWD}" | cryptsetup open $MAIN_PARTITION cryptlvm - || { echo "LUKS open failed"; exit 1; }
}

# Create physical and logical volumes
create_volumes() {
    echo "Create volumes"
    pvcreate /dev/mapper/cryptlvm || { echo "pvcreate failed"; exit 1; }
    vgcreate vg1 /dev/mapper/cryptlvm || { echo "vgcreate failed"; exit 1; }
    lvcreate -L 40G vg1 -n root || { echo "lvcreate root failed"; exit 1; }
    lvcreate -L 8G vg1 -n swap || { echo "lvcreate swap failed"; exit 1; }
    lvcreate -l 100%FREE vg1 -n home || { echo "lvcreate home failed"; exit 1; }
}

# Format partitions
format_partitions() {
    echo "Format partitions"
    mkfs.fat -F32 $UEFI_PARTITION || { echo "mkfs.fat failed"; exit 1; }
    mkfs.ext4 /dev/vg1/root || { echo "mkfs.ext4 root failed"; exit 1; }
    mkfs.ext4 /dev/vg1/home || { echo "mkfs.ext4 home failed"; exit 1; }
    mkswap /dev/vg1/swap || { echo "mkswap failed"; exit 1; }
}

# Mount file system
mount_file_system() {
    echo "Mount file system"
    mount /dev/vg1/root /mnt || { echo "mount root failed"; exit 1; }
    mkdir -p /mnt/home
    mount /dev/vg1/home /mnt/home || { echo "mount home failed"; exit 1; }
    mkdir -p /mnt/boot
    mount $UEFI_PARTITION /mnt/boot || { echo "mount boot failed"; exit 1; }
    swapon /dev/vg1/swap || { echo "swapon failed"; exit 1; }
}

# Install base
install_base() {
    echo "Install base"
    # Pacstrap latest Arch base and latest kernel
    pacstrap /mnt base linux linux-firmware neovim intel-ucode lvm2

    # Generate filesystem table
    genfstab -U /mnt >> /mnt/etc/fstab
}

# Configure system
chroot() {
    echo "Configure system"
    cp install.sh /mnt/root/install.sh
    chmod +x /mnt/root/install.sh
    arch-chroot /mnt /root/install.sh setupchroot
}

# Timezone
timezone() {
    echo "Timezone"
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    hwclock --systohc
}

# Localization
localization() {
    echo "Localization"
    # Add locale only if not present
    if ! grep -q '^en_DK.UTF-8 UTF-8' /etc/locale.gen; then
        echo "en_DK.UTF-8 UTF-8" >> /etc/locale.gen
    fi
    locale-gen
    echo "LANG=en_DK.UTF-8" > /etc/locale.conf
    # Only add keymap if not present
    if ! grep -q "^KEYMAP=${KEYMAP}$" /etc/vconsole.conf 2>/dev/null; then
        echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
    fi
}

# Network configuration
network_configuration() {
    echo "Network configuration"
    echo "$HOST_NAME" > /etc/hostname
    echo "" >> /etc/hosts
    echo "127.0.0.1     localhost" >> /etc/hosts
    echo "::1           localhost" >> /etc/hosts
    echo "127.0.1.1     ${HOST_NAME}.localdomain   ${HOST_NAME}" >> /etc/hosts
}

# Set root password
set_root_passwd() {
    echo "Set root password"
    echo -n "root:${PASSWD}" | chpasswd
}

# Install packages
install_packages() {
    echo "Install packages"
    pacman -Sy --noconfirm powertop grub efibootmgr networkmanager network-manager-applet wireless_tools wpa_supplicant dialog mtools dosfstools base-devel linux-headers git reflector bluez bluez-utils pipewire pipewire-pulse cups xdg-utils xdg-user-dirs
}

# Initramfs
initramfs() {
    echo "Initramfs"
    HOOKS=$(cat /etc/mkinitcpio.conf | grep "^HOOKS=(")
    MOD_HOOKS=""
    for i in $HOOKS
    do
        if [[ "$i" == "autodetect" ]]; then
            HOOK="$i keymap"
        elif [[ "$i" == "filesystems" ]]; then
            HOOK="encrypt lvm2 resume $i"
        else
            HOOK="$i"
        fi
        MOD_HOOKS="${MOD_HOOKS} ${HOOK}"
    done
    MOD_HOOKS=${MOD_HOOKS:1}

    sed -i "s/^HOOKS=(.*/${MOD_HOOKS}/g" /etc/mkinitcpio.conf

    mkinitcpio -p linux
}

# Install bootloader
bootloader() {
    echo "Install bootloader"
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    MAIN_PARTITION=$(fdisk -l $DISK | grep 'LVM' | awk '{print $1}')
    MAIN_PARTITION_UUID=$(blkid | grep $MAIN_PARTITION | awk '{print $2}')
    GRUB_CMD="cryptdevice=${MAIN_PARTITION_UUID}:cryptlvm root=\/dev\/vg1\/root resume=\/dev\/mapper\/vg1-swap"
    sed -i "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"${GRUB_CMD}\"/g" /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
}

# Add user
add_user() {
    echo "Add user"
    useradd -mG wheel $USER
    echo -n "${USER}:${PASSWD}" | chpasswd
    # Safely enable wheel group sudo using visudo
    if ! grep -q '^%wheel ALL=(ALL) ALL' /etc/sudoers; then
        EDITOR="sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/'" visudo
    fi
}

# Video driver
video_driver() {
    echo "Install video driver"
    if lspci | grep -i 'vga' | grep -qi 'Intel'; then
        echo "Intel GPU detected. Installing xf86-video-intel."
        pacman -Sy --noconfirm xf86-video-intel
    fi
    if lspci | grep -i 'vga' | grep -qi 'NVIDIA'; then
        echo "NVIDIA GPU detected. Installing nvidia drivers."
        pacman -Sy --noconfirm nvidia nvidia-utils nvidia-settings
    fi
    if lspci | grep -i 'vga' | grep -qi 'AMD'; then
        echo "AMD GPU detected. Installing xf86-video-amdgpu."
        pacman -Sy --noconfirm xf86-video-amdgpu
    fi
}

# Desktop
install_desktop() {
    echo "Install KDE Plasma (Wayland) and display manager"
    pacman -Sy --noconfirm plasma-meta plasma sddm plasma-wayland-session
    systemctl enable sddm
}

# Enable services
enable_services() {
    echo "Enable services"
    systemctl enable NetworkManager
    systemctl enable bluetooth
    systemctl enable cups.service
}

if [[ $1 == bootstrap ]]; then
    chrootsetupbootstrap
elif [[ $1 == setupchroot ]]; then
    chrootsetup
else
    setup
fi
