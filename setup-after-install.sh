#!/bin/bash

# tested on a ThinkPad X260

set -exo pipefail

export VISUAL=vim
export EDITOR=vim

# Install yay (AUR helper)
if ! item="$(type -p "yay")" || [[ -z $item ]]; then
    echo "yay is not installed"
    sudo pacman -S --noconfirm --needed base-devel git
    mkdir -p ~/.software
    cd ~/.software
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ../..
fi

sudo pacman -S --noconfirm --needed wget

# Download and validate package lists
wget -q -O pacman-list.pkg https://gist.githubusercontent.com/alessap/3120fb734b7257d6656da33820630612/raw/0dc9d1d84d56b595c0da572ee6a60c244213f237/pacman-list.pkg
if ! grep -qE '^[a-zA-Z0-9_-]+$' pacman-list.pkg; then
    echo "pacman-list.pkg failed validation. Aborting."
    rm pacman-list.pkg
    exit 1
fi
sudo pacman -S --noconfirm --needed - < pacman-list.pkg
rm pacman-list.pkg

wget -q -O aur-list.pkg https://gist.githubusercontent.com/alessap/2e0a6863da0a9cc8195f5f50369a5852/raw/f0779a8dc2ac860aaa2dd513a9293846752cbfcd/aur-list.pkg
if ! grep -qE '^[a-zA-Z0-9_-]+$' aur-list.pkg; then
    echo "aur-list.pkg failed validation. Aborting."
    rm aur-list.pkg
    exit 1
fi
sed '/pug/d' aur-list.pkg > aur-list-no-pug.pkg
xargs -a aur-list-no-pug.pkg yay -S --noconfirm --needed --removemake
rm aur-list*pkg

cd
[[ ! -e ~/.ssh/id_rsa ]] && ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N ""
cat ~/.ssh/id_rsa.pub
read -p "Add SSH key on your github page and press [Yy] to continue: " -n 1 -r

if [ ! -e dotfiles ]; then
git clone git@github.com:alessap/dotfiles.git
cd dotfiles
bash create_links.sh
cd ..
fi

# Install powerline-shell
if [ ! -e  ~/.software/powerline-shell ];  then
    mkdir -p ~/.software
    cd ~/.software
    git clone https://github.com/b-ryan/powerline-shell
    cd powerline-shell
    pip install --user .
    cd ../..
fi

# Install powerline fonts
if [ ! -e  ~/.software/fonts ];  then
mkdir -p ~/.software
cd ~/.software
# clone
git clone https://github.com/powerline/fonts.git --depth=1
# install
cd fonts
./install.sh
# clean-up a bit
cd ../..
fi

# Install fingerprint reader 
sudo pacman -S --noconfirm --needed fprintd imagemagick

# Cheese not working on gnome - camera
if [ -z "$USER" ]; then
    read -p "Enter your username for video group and other user-specific steps: " USER
fi
sudo usermod -a -G video "$USER"
read -p "Disable PipeWire system-wide? This may break modern audio setups. [y/N]: " disable_pw
if [[ "$disable_pw" =~ ^[Yy]$ ]]; then
    sudo systemctl --global disable pipewire.socket
    echo "PipeWire disabled. You may need to reboot."
else
    echo "PipeWire not disabled. If you have audio issues, revisit this step."
fi
# and reboot

# set grub timeout
GRUB_TIMEOUT="0"  # set to 0 to skip grub menu in case there is no dual boot
sudo sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=${GRUB_TIMEOUT}/g" /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg

# pacaur -S pug
