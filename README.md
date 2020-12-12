# Archlinux installer script - base system and more

Forked from wcarlsen/archlinux-install

This install installer script will install [Archlinux](https://www.archlinux.org/) as I prefer it. Input options included in the script:

| Input | Description |
|---|---|
| DISK | Which disk to install on. |
| COUNTRY | Choose country. |
| KEYMAP | Keymap used. |
| HOST_NAME | Hostname to apply to install. |
| PASSWD | Password used for disk encryption and login. |
| USER | Username. |
| TIMEZONE | Current timezone. |
| DESKTOP | Gnome or KDE for desktop environment. |


## Get started

Download Arch Linux iso from https://www.archlinux.org/download/

Create a new `msdos` partition on your USB drive (e.g. using gparted)

Create a FAT32 primary partition

The next command might be very dangerous: double check the disk name before executing (e.g. sudo fdisk -l). 
Open a terminal and run (do not use /dev/sdXn but /dev/sdX):
```bash
sudo dd bs=4M if=path/to/archlinux/iso of=/dev/sdX && sync  
```
Now the drive is ready for installing Arch on your computer.

Load the install media. And follow these steps

```bash
# Load keymap
loadkeys dk-latin1

iw dev

ip link set wlan0 up

iw dev wlan0 scan
 
wpa_passphrase MYSSID passphrase > /etc/wpa_supplicant/example.conf

wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/example.conf
dhcpcd wlan0

# Check internet connection
ping https://wwww.archlinux.org/

# Find name of disk to install Archlinux on
lsblk

# Fetch install script
curl -o install.sh https://raw.githubusercontent.com/alessap/archlinux-install/main/install.sh

# Change input variables to your liking
vim install.sh

# Make executable
chmod +x install.sh

# Run script
./install.sh

# Post install
exit
umount -a
reboot
```
