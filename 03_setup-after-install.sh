#!/usr/bin/env bash
# tested on a ThinkPad X260
# Safer, idempotent adaptations: preflight checks, ed25519 keys,
# safer yay build, and clearer prompts. Intended for interactive use.

set -euo pipefail

VISUAL=${VISUAL:-vim}
EDITOR=${EDITOR:-vim}

SCRIPT_NAME=$(basename "$0")
NONINTERACTIVE=0

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--non-interactive]

Options:
  --non-interactive   run without prompts (will abort if confirmation needed)
  -h, --help          show this help
EOF
}

for arg in "$@"; do
    case "$arg" in
        --non-interactive) NONINTERACTIVE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) ;;
    esac
done

log() { printf '%s\n' "$*" >&2; }

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log "Required command not found: $1";
        exit 1;
    fi
}

cd "$HOME"

# Preflight checks
require_cmd git
require_cmd ssh-keygen
require_cmd bash

# pacman/makepkg may not be available in chroot-less environments;
# check them only when we need to install system packages.

install_yay() {
    if command -v yay >/dev/null 2>&1; then
        log "yay already installed"
        return 0
    fi

    log "Installing yay (AUR helper)"
    if ! command -v pacman >/dev/null 2>&1 || ! command -v makepkg >/dev/null 2>&1; then
        log "pacman or makepkg not found — cannot build yay. Aborting."
        return 1
    fi

    # install build deps if missing
    sudo pacman -S --noconfirm --needed base-devel git || {
        log "Failed to install base-devel/git"; return 1
    }

    mkdir -p "$HOME/.software/build-yay"
    pushd "$HOME/.software/build-yay" >/dev/null
    if [ -d yay ]; then
        git -C yay pull --ff-only || git -C yay fetch --all
    else
        git clone https://aur.archlinux.org/yay.git
    fi
    cd yay
    makepkg -si --noconfirm || { log "makepkg failed"; popd >/dev/null; return 1; }
    popd >/dev/null
}

# SSH key: prefer ed25519, generate only if no key exists
generate_ssh_key() {
    # prefer ed25519; fallback to rsa if requested
    SSH_DIR="$HOME/.ssh"
    mkdir -p "$SSH_DIR"
    if ls "$SSH_DIR"/*ed25519 >/dev/null 2>&1 || ls "$SSH_DIR"/*rsa >/dev/null 2>&1; then
        log "SSH key already exists; skipping generation"
        return 0
    fi

    KEY_TYPE="ed25519"
    KEY_FILE="$SSH_DIR/id_${KEY_TYPE}"
    if [ "$NONINTERACTIVE" -eq 1 ]; then
        ssh-keygen -t "$KEY_TYPE" -f "$KEY_FILE" -N "" -q || return 1
    else
        ssh-keygen -t "$KEY_TYPE" -f "$KEY_FILE" -N ""
        log "Public key:"; cat "${KEY_FILE}.pub"
        read -r -p "Add SSH key on your github page and press Y to continue: " response
        case "$response" in
            [Yy]*) log "Continuing..." ;;
            *) log "Please add the key and re-run the script."; exit 1 ;;
        esac
    fi
}

install_or_update_dotfiles() {
    DOTFILES_DIR="$HOME/dotfiles"
    if [ -d "$DOTFILES_DIR/.git" ]; then
        log "Dotfiles repo exists — pulling latest"
        git -C "$DOTFILES_DIR" pull --ff-only || log "Failed to pull dotfiles (manual intervention may be required)"
    else
        git clone git@github.com:alessap/dotfiles.git "$DOTFILES_DIR" || { log "Failed to clone dotfiles"; return 1; }
    fi

    if [ -x "$DOTFILES_DIR/create_links.sh" ]; then
        bash "$DOTFILES_DIR/create_links.sh"
    else
        log "create_links.sh not found or not executable in dotfiles"
    fi
}

install_powerline_shell() {
    PL_DIR="$HOME/.software/powerline-shell"
    if [ -d "$PL_DIR" ]; then
        log "powerline-shell already present"
        return 0
    fi

    mkdir -p "$HOME/.software"
    git clone https://github.com/b-ryan/powerline-shell "$PL_DIR" --depth=1 || { log "Failed to clone powerline-shell"; return 1; }

    if command -v pipx >/dev/null 2>&1; then
        pipx install --spec "$PL_DIR" "$PL_DIR" || pip install --user "$PL_DIR"
    elif command -v pip >/dev/null 2>&1; then
        pip install --user "$PL_DIR" || { log "pip install failed"; return 1; }
    else
        log "pip/pipx not found; skipping powerline-shell install"
    fi
}

install_powerline_fonts() {
    FONTS_DIR="$HOME/.software/fonts"
    if fc-list | grep -i powerline >/dev/null 2>&1; then
        log "Powerline fonts already installed"
        return 0
    fi

    mkdir -p "$HOME/.software"
    if [ -d "$FONTS_DIR" ]; then
        log "Fonts repo already cloned"
    else
        git clone https://github.com/powerline/fonts.git --depth=1 "$FONTS_DIR" || { log "Failed to clone fonts"; return 1; }
    fi
    if [ -x "$FONTS_DIR/install.sh" ]; then
        bash "$FONTS_DIR/install.sh" || { log "Font install failed"; return 1; }
        fc-cache -f >/dev/null || true
    else
        log "Fonts install script missing or not executable"
    fi
}

# Main flow
install_yay
generate_ssh_key
install_or_update_dotfiles
install_powerline_shell
install_powerline_fonts

log "Setup script completed"


