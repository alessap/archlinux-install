# Archlinux installer script - base system and more

Forked from wcarlsen/archlinux-install

This install installer script will install [Archlinux](https://www.archlinux.org/) as I prefer it. Input options included in the script:

| Input | Description |
|---|---|
| DISK | Which disk to install on. Prompted at runtime. |
| COUNTRY | Country for mirrorlist. Prompted at runtime. |
| KEYMAP | Keymap used. Prompted at runtime. |
| HOST_NAME | Hostname for the install. Prompted at runtime. |
| PASSWD | Password for disk encryption and login. Prompted securely at runtime. |
| USER | Username. Prompted at runtime. |
| TIMEZONE | Timezone. Prompted at runtime. |
| DESKTOP | KDE Plasma (Wayland) is installed by default. |


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


# No need to edit variables in the script. All required values are prompted interactively and securely.

# Make executable
chmod +x install.sh

# Run script
./install.sh

# Post install
exit
umount -a
reboot
```

## Hardware and Post-Install Support

- **KDE Plasma (Wayland)** is installed by default, with SDDM as the display manager.
- **Fingerprint login**: fprintd is installed. For Validity sensors, install `python-validity` from AUR after first boot.
- **Face recognition login**: Howdy is installed via AUR (requires yay).
- **Touchscreen & Pen**: xf86-input-wacom and libwacom are installed for pen/touch support (e.g., ThinkPad X1 Yoga).
- **Gyroscope/Screen rotation**: iio-sensor-proxy is installed for automatic screen rotation on convertibles/2-in-1s.
- **On-screen keyboard**: For touch use, consider installing `onboard` or `maliit-keyboard`.

### AUR Helper
The post-install script will install `yay` (AUR helper) if not present, and use it for AUR packages like Howdy.

### Dotfiles
If you have a dotfiles repo, it will be cloned and symlinked after install.

### SSH Key
If you do not have an SSH key, one will be generated and you will be prompted to add it to GitHub.

---
This setup is tested on ThinkPad X1 Yoga and similar 2-in-1s, but should work on most modern laptops. For any hardware-specific issues, check the Arch Wiki or open an issue.
