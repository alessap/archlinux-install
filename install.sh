#!/bin/bash

set -euxo pipefail

# Update system clock
timedatectl set-ntp true

# Create mirrorlist
pacman -Syy --noconfirm reflector
reflector -c Denmark -a 6 --sort rate --save /etc/pacman.d/mirrorlist
pacman -Syyy

# Zap disk
sgdisk --zap-all

# Parition disk
gdisk $DISK << GDISK_CMDS
n
1

+260M
ef00
n
2


8e00
w
Y
GDISK_CMDS

UEFI_PARTITION=$(fdisk -l $DISK | grep 'EFI' | awk '{print $1}')
MAIN_PARTITION=$(fdisk -l $DISK | grep 'LVM' | awk '{print $1}')

# Encrypt main partition
echo $PASSWD | cryptsetup luksFormat $MAIN_PARTITION -d -
echo $PASSWD | cryptsetup open $MAIN_PARTITION cryptlvm -d -

pvcreate /dev/mapper/cryptlvm
vgcreate vg1 /dev/mapper/cryptlvm
lvcreate -L 40G vg1 -n root
lvcreate -L 2G vg1 -n swap
lvcreate -l 100%FREE vg1 -n home

# Format partitions
mkfs.fat -F32 $UEFI_PARTITION
mkfs.ext4 /dev/vg1/root
mkfs.ext4 /dev/vg1/home
mkswap /dev/vg1/swap

# Mount file system
mount /dev/vg1/root /mnt
mkdir /mnt/home
mount /dev/vg1/home /mnt/home
mkdir /mnt/boot
mount $UEFI_PARTITION /mnt/boot
swapon /dev/vg1/swap

# Pacstrap
pacstrap /mnt base linux linux-firmware neovim intel-ucode lvm2

# Generate filesystem table
genfstab -U /mnt >> /mnt/etc/fstab

# Configure system
cp install.sh /mnt/root/install.sh
chmod + /mnt/root/install.sh
arch-chroot /mnt /root/install.sh setupchroot

# Unmount and reboot
umount -a
reboot

setupchroot() {
    # Timezone
    ln -sf /usr/share/zoneinfo/Europe/Copenhagen /etc/localtime
    hwclock --systohc

    # Localization
    echo 'en_US.UTF-8 UTF-8' /etc/locale.gen # en_US.UTF-8 UTF-8
    locale-gen
    echo LANG=en_US.UTF-8 >> /etc/locale.conf
    echo KEYMAP=dk >> /etc/vconsole.conf

    # Network configuration
    echo $HOSTNAME >> /etc/hostname
    echo '127.0.0.1     localhost' > /etc/hosts
    echo '::1           localhost' > /etc/hosts
    echo '127.0.1.1     $HOSTNAME.localdomain   $HOSTNAME' > /etc/hosts

    # Set root password
    echo 'root:$PASSWD' | chpasswd

    # Install packages
    pacman -Sy --noconfirm grub efibootmgr networkmanager network-manager-applet wireless_tools wpa_supplicant dialog mtools dosfstools base-devel linux-headers git reflector bluez bluez-utils pulseaudio-bluetooth cups xdg-utils xdg-user-dirs

    # Initramfs
    # sed -i "s/"
    # mkinitcpio -p linux

    # # Install bootloader
    # grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

    # MAIN_PARTITION_UUID=$(blkid | grep $MAIN_PARTITION | awk '{print $2}')
    # GRUB_CMD='cryptdevice=$MAIN_PARTITION_UUID:cryptlvm root=/dev/vg1/root'
    # sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="$GRUB_CMD"'
    # grub-mkconfig -o /boot/grub/grub.cfg

    # # Enable services
    # systemctl enable NetworkManager
    # systemctl enable bluetooth
    # systemctl enable org.cups.cupsd

    # # Add user
    # useradd -mG wheel wcarlsen
    # passwd wcarlsen
    # sed -i "s/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/" /etc/sudoers

    # exit
}