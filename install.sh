#!/bin/bash

# tested on a ThinkPad X260

set -exo pipefail

# Configuration
DISK="/dev/sda"
COUNTRY="Denmark"
KEYMAP="dk-latin1"
HOST_NAME="archlinux-x260"
PASSWD="A Very Secret Password"
USER="alessap"
TIMEZONE="Europe/Copenhagen"
DESKTOP="gnome"

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
    sgdisk --zap-all $DISK
}

# Parition disk
partition_disk() {
    echo "Partion disk ${DISK}"
    sgdisk -n 0:0:+260M -t 0:ef00 $DISK
    sgdisk -n 0:0:0 -t 0:8e00 $DISK

    UEFI_PARTITION=$(fdisk -l $DISK | grep 'EFI' | awk '{print $1}')
    MAIN_PARTITION=$(fdisk -l $DISK | grep 'LVM' | awk '{print $1}')
}


# Encrypt main partition
encrypt_main_partition() {
    echo "Encrypt main partition"
    echo -n "${PASSWD}" | cryptsetup luksFormat $MAIN_PARTITION -
    echo -n "${PASSWD}" | cryptsetup open $MAIN_PARTITION cryptlvm -
}

# Create physical and logical volumes
create_volumes() {
    echo "Create volumes"
    pvcreate /dev/mapper/cryptlvm
    vgcreate vg1 /dev/mapper/cryptlvm
    lvcreate -L 40G vg1 -n root
    lvcreate -L 8G vg1 -n swap
    lvcreate -l 100%FREE vg1 -n home
}

# Format partitions
format_partitions() {
    echo "Format partitions"
    mkfs.fat -F32 $UEFI_PARTITION
    mkfs.ext4 /dev/vg1/root
    mkfs.ext4 /dev/vg1/home
    mkswap /dev/vg1/swap
}

# Mount file system
mount_file_system() {
    echo "Mount file system"
    mount /dev/vg1/root /mnt
    mkdir /mnt/home
    mount /dev/vg1/home /mnt/home
    mkdir /mnt/boot
    mount $UEFI_PARTITION /mnt/boot
    swapon /dev/vg1/swap
}

# Install base
install_base() {
    echo "Install base"
    # Pacstrap
    pacstrap /mnt base linux linux-firmware neovim intel-ucode lvm2

    # Generate filesystem table
    genfstab -U /mnt >> /mnt/etc/fstab
}

# Configure system
chroot() {
    echo "Configure system"
    cp install.sh /mnt/root/install.sh
    chmod + /mnt/root/install.sh
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
    echo "" >> /etc/locale.gen
    echo "en_DK.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    echo "LANG=en_DK.UTF-8" >> /etc/locale.conf
    echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
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
    pacman -Sy --noconfirm powertop vim grub efibootmgr networkmanager network-manager-applet wireless_tools wpa_supplicant dialog mtools dosfstools base-devel linux-headers git reflector bluez bluez-utils pulseaudio-bluetooth cups xdg-utils xdg-user-dirs
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
    sed -i "s/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/" /etc/sudoers
}

# Video driver
video_driver() {
    echo "Install video driver"
    pacman -Sy --noconfirm xf86-video-intel
    if lspci | grep -q 'NVIDIA'; then
        pacman -Sy --noconfirm nvidia nvidia-utils nvidia-settings
    fi
}

# Desktop
install_desktop() {
    echo "Install desktop and display server"
    if [[ $DESKTOP == "gnome" ]]; then
        pacman -Sy --noconfirm xorg gnome gnome-tweaks
        systemctl enable gdm
    elif [[ $DESKTOP == "kde" ]]; then
        pacman -Sy --noconfirm plasma kde-applications sddm
        systemctl enable sddm
    else
        echo 'No valid desktop specified'
    fi
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
