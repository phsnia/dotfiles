#!/usr/bin/env bash

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly RESET='\033[0m'

# Log helpers
info() {
    echo -e "${BLUE}==>${RESET} $*"
}

success() {
    echo -e "${GREEN}==>${RESET} $*"
}

warn() {
    echo -e "${YELLOW}==>${RESET} $*"
}

error() {
    echo -e "${RED}==>${RESET} $*" >&2
}

#!/usr/bin/env bash
set -Eeuo pipefail

# Install packages that are not already installed.
#
# @param {...string} pkg - Package names to install.
# @example
# install git curl neovim
install() {
    local pkg
    local -a missing=()

    for pkg in "$@"; do
        if ! pacman -Q "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if ((${#missing[@]})); then
        sudo pacman -S --needed --noconfirm "${missing[@]}"
    fi
}

# --- System ---
sudo pacman -Syu --needed --noconfirm

# --- Core ---
core() {
    install \ 
        git \ 
        base-devel \ 
        vim \ 
        alacritty 
}

# --- Drivers ---
drivers() {
    install \
        mesa \
        intel-media-driver \
        libva-intel-driver \
        vulkan-intel \
        vulkan-radeon \
        xf86-video-amdgpu \
        xf86-video-ati \
        vulkan-nouveau \
        xf86-video-nouveau
}

utilies() {
    # --- Window Manager Enviroment ---
    install \
        i3 \
        xorg-server \
        xorg-xinit \
        ly \
        dmenu \
        neovim \
        feh \
        htop

    # 
    # udiskie

    echo -e "${GREEN}==>${RESET} Configuring ly..."
    
    echo -e "  ${BLUE}->${RESET} Checking ly service"
    sudo systemctl is-enabled ly@tty1.service &>/dev/null ||
    
    echo -e "  ${BLUE}->${RESET} Enable ly service"
    sudo systemctl enable ly@tty1.service

    echo -e "${GREEN}==>${RESET} Configuring ly..."

    # --- Audio ---
    echo -e "${GREEN}==>${RESET} Installing audio..."
    install \
        pipewire \
        pipewire-pulse \
        pavucontrol \
        alsa-utils \
        sof-firmware
    echo -e "${GREEN}==>${RESET} Installation completely..."

    echo -e "  ${BLUE}->${RESET} Adding ${USER} to docker group"
    sudo usermod -aG docker "$USER"

    echo -e "${GREEN}==>${RESET} Docker configured successfully"

    # --- Packages manager ---
    if ! command -v yay &>/dev/null; then
        if [[ ! -d "$HOME/yay/.git" ]]; then
            git clone https://aur.archlinux.org/yay.git "$HOME/yay"
        else 
            git -C "$HOME/yay" pull --ff-only
        fi

        (
            cd "$HOME/yay"
            makepkg -si --noconfirm
        )
    fi
    # --- AUR Packages ---
    yay -S --needed --noconfirm \
        brave-bin \
        zed \
        visual-studio-code-bin
}

dev_kit() {   
    sudo pacman -Syu
    echo "--- Developer kit ---"
    install mise # install 
    install docker docker-compose

    echo -e "${GREEN}==>${RESET} Configuring Docker..."
    echo -e "  ${BLUE}->${RESET} Enabling Docker service"
    sudo systemctl enable --now docker
    echo -e "${GREEN}==>${RESET} Apply docker to group..."

    # --- System kit ---
    # this include tool like GNU toolchain, debugger
    install clang \
        gdb \
        lldb \
        cmake \
        ninja \
        valgrind
    install c3c
    echo -e "  ${BLUE}->${RESET} Installing Zig globally..."
    mise use -g zig

    # --- Enterpise kit ---
    echo -e "  ${BLUE}->${RESET} Installing Dotnet globally..."
    mise use -g dotnet

    # --- Mobile kit ---
    yay -S --needed --noconfirm jetbrains-toolbox
    install scrcpy 

    # --- IDE ---
    yay -S --needed --noconfirm zed visual-studio-code-bin

    echo -e "${GREEN}==>${RESET} Developer Kit installation complete."
}

fonts() {
    # --- Fonts (optional) ---
    # this is optional I prefer use Comic Mono so yah
    install noto-fonts \
        noto-fonts-cjk \
        noto-fonts-emoji \
        noto-fonts-extra \
        ttf-dejavu \
        ttf-liberation
}

dev_kit
fonts
