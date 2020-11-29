# Archlinux installer script

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
Load the install media. And follow these steps

```bash
# Load keymap
loadkeys dk

# Check internet connection
ping https://wwww.archlinux.org/

# Find name of disk to install Archlinux on
lsbllk

# Fetch install script
curl -o install.sh https://raw.githubusercontent.com/wcarlsen/archlinux-install/main/install.sh

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