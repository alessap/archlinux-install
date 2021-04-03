#!/bin/bash

# tested on a ThinkPad X260

set -exo pipefail

export VISUAL=vim
export EDITOR=vim

# Install pacaur
if ! item="$(type -p "pacaur")" || [[ -z $item ]]; then
    echo "pacaur is not installed"
    sudo pacman -S --noconfirm --needed base-devel git
    
    mkdir -p ~/.software
    cd ~/.software
    sudo pacman -Syu --noconfirm --needed jq expac 

    git clone https://aur.archlinux.org/auracle-git.git
    cd auracle-git
    makepkg -si
    cd ..

    git clone https://aur.archlinux.org/pacaur.git
    cd pacaur
    makepkg -si
    cd ../..
fi

sudo pacman -S --noconfirm --needed wget

wget -q -O pacman-list.pkg https://gist.githubusercontent.com/alessap/3120fb734b7257d6656da33820630612/raw/0dc9d1d84d56b595c0da572ee6a60c244213f237/pacman-list.pkg 
sudo pacman -S --noconfirm --needed - < pacman-list.pkg
rm pacman-list.pkg

wget -q -O aur-list.pkg https://gist.githubusercontent.com/alessap/2e0a6863da0a9cc8195f5f50369a5852/raw/f0779a8dc2ac860aaa2dd513a9293846752cbfcd/aur-list.pkg
sed '/pug/d' aur-list.pkg > aur-list-no-pug.pkg 
xargs <aur-list-no-pug.pkg pacaur -S --noconfirm --needed --noedit 
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
sudo python setup.py install
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
sudo usermod -a -G video alessap
sudo systemctl --global disable pipewire.socket
# and reeboot

# set grub timeout
GRUB_TIMEOUT="0"  # set to 0 to skip grub menu in case there is no dual boot
sudo sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=${GRUB_TIMEOUT}/g" /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg

# pacaur -S pug
