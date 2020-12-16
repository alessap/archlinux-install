#!/bin/bash

set -exo pipefail

# Install pacaur
install_pacaur() {
    echo "Install pacaur"
    if ! item="$(type -p "pacaur")" || [[ -z $item ]]; then
        echo "pacaur is not installed"
        sudo pacman -S --noconfim --needed base-devel git
        
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
        cd ..
    else
        echo "pacaur is already installed, doing nothing"
    fi
}

sudo pacman -S --noconfirm --needed wget

wget -q -O pacman-list.pkg https://gist.githubusercontent.com/alessap/d006fbae581c07077a3fa8185802ff01/raw/067e745c1cd53b763ac0a917c5a695ed1212849c/pacman-list.pkg
sudo pacman -S --needed - < pacman-list.pkg
rm pacman-list.pkg

wget -q -O aur-list.pkg https://gist.githubusercontent.com/alessap/bb661806b5bd3f4554eb60df5308aa33/raw/13d4ba2df8656c1e1b52f03e0eba10b8d0b2cc41/aur-list.pkg
xargs <aur-list.pkg pacaur -S --needed --noedit 
rm aur-list.pkg

cd
[[ .ssh/id_rsa ]] && ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N ""

git clone git@github.com:alessap/dotfiles.git
cd dotfiles
bash create_links.sh

# Install powerline-shell
mkdir -p ~/.software
cd ~/.software
git clone https://github.com/b-ryan/powerline-shell
cd powerline-shell
sudo python setup.py install
cd ../..

# Install powerline fonts
mkdir -p ~/.software
cd ~/.software
# clone
git clone https://github.com/powerline/fonts.git --depth=1
# install
cd fonts
./install.sh
# clean-up a bit
cd ..
rm -rf fonts

# Install fingerprint reader 
sudo pacman -S fprintd imagemagick

# Cheese not working on gnome - camera
sudo usermod -a -G video alessap
systemctl --global disable pipewire.socket
# and reeboot