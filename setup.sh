#!/bin/bash

# tested on a ThinkPad X260
# Run this as your user


set -exo pipefail

# Main setup
setup() {
    set_keymap
    install_google_chrome
}

# Set keymap
set_keymap() {
    echo "Set keymap"
    setxkbmap dk 
}


# Install Google Chrome
install_google_chrome() {
    echo "Install Google Chrome"
}

setup