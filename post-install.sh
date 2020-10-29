#!/bin/bash

set -exo pipefail

setup() {
    install_yay
}

# Yay
install_yay() {
    echo "Install yay"
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si
}