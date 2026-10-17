#!/usr/bin/env bash
#
# bootstrap.sh — Arch Linux dotfiles installer & configurator
#
# Combines the former linux/arch/{config.sh,c.sh,install.sh} into one
# readable, structured entry point.
#
# Usage:
#   ./bootstrap.sh                         # run every stage
#   ./bootstrap.sh system dotfiles polkit  # run only the named stages
#
# Stages: system, dotfiles, polkit, core, drivers, utilities, devkit, fonts
#
set -Eeuo pipefail

# Directories

readonly DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_DIR="$HOME/.config"
readonly DOTFILES_CONFIG="$DOTFILES_DIR/.config"

# Polkit mount rule is written for this user (override with POLKIT_USER).
readonly POLKIT_USER="${POLKIT_USER:-phng}"

# Colors & log helpers

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly RESET='\033[0m'

# Log helpers
#
# Level-based indentation: each level adds one leading tab.
#   info 0 "msg"   -> ==> msg
#   info 1 "msg"   -> 	==> msg
#   info "msg"     -> ==> msg   (level defaults to 0)
#
# Arrows:
#   info/success/warn/error  -> ==>
#   step                     -->   (sub-step)

_log() {
    local color="$1" arrow="$2"; shift 2

    local level=0
    if (($# > 1)) && [[ "$1" =~ ^[0-9]+$ ]]; then
        level="$1"; shift
    fi

    local indent=""
    local i
    for ((i = 0; i < level; i++)); do
        indent+=$'\t'
    done

    echo -e "${indent}${color}${arrow}${RESET} $*"
}

info()   { _log "${BLUE}"  "==>" "$@"; }
success() { _log "${GREEN}" "==>" "$@"; }
warn()   { _log "${YELLOW}" "==>" "$@"; }
error()  { _log "${RED}"   "==>" "$@" >&2; }

step() {
    _log "${BLUE}" "->" "$@"
}

# Helpers

# Install packages that are not already installed.
#
# @param {...string} pkg - Package names to install.
# @example
#   install git curl neovim
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

# --- Stages ---

# --- System: timezone & NTP ---

# Configure system timezone and NTP.
#
# @example
#   system
system() {
    info "Configuring system time..."
    sudo timedatectl set-timezone Asia/Ho_Chi_Minh
    sudo timedatectl set-ntp true
    success "System time configured."
}

# --- Dotfiles ---

# Symlink dotfiles config directories and .bashrc into $HOME.
#
# @example
#   dotfiles
dotfiles() {
    info "Linking dotfiles..."

    ln -sfn "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"

    local -a CONFIGS=(
        i3
        alacritty
    )
    for config in "${CONFIGS[@]}"; do
        ln -sTfn "$DOTFILES_CONFIG/$config" "$CONFIG_DIR/$config"
    done

    success "Dotfiles linked."
}

# --- Polkit ---

# Install polkit/udiskie and write the udiskie mount polkit rule for $POLKIT_USER.
#
# @example
#   polkit
polkit() {
    info "Installing polkit / udiskie and configuring mount rules..."

    sudo pacman -S --needed polkit udiskie
    sudo mkdir -p /etc/polkit-1/rules.d

    sudo tee /etc/polkit-1/rules.d/49-mount.rules > /dev/null <<EOF
polkit.addRule(function(action, subject) {
    if (subject.user === "${POLKIT_USER}" &&
        (action.id === "org.freedesktop.udisks2.filesystem-mount" ||
         action.id === "org.freedesktop.udisks2.filesystem-mount-system" ||
         action.id === "org.freedesktop.udisks2.filesystem-unmount-others")) {
        return polkit.Result.YES;
    }
});
EOF

    success "Polkit rules written to /etc/polkit-1/rules.d/49-mount.rules"
}

# --- Core packages ---

# Install core system packages (git, base-devel, vim, alacritty).
#
# @example
#   core
core() {
    info "Installing core packages..."
    install \
        git \
        base-devel \
        vim \
        alacritty
    success "Core packages installed."
}

# --- Graphics drivers ---

# Install graphics drivers for Intel, AMD, NVIDIA and Nouveau GPUs.
#
# @example
#   drivers
drivers() {
    info "Installing graphics drivers..."
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
    success "Graphics drivers installed."
}

# --- Utilities  ---

# Install window manager, Xorg, audio stack, yay (AUR helper) and AUR apps.
# Also enables the ly display manager and adds $USER to the docker group.
#
# @example
#   utilities
utilities() {
    info "Installing utilities, window manager and audio..."

    install \
        i3 \
        xorg-server \
        xorg-xinit \
        ly \
        dmenu \
        neovim \
        feh \
        htop

    # Configure ly display manager
    info "Configuring ly..."
    if ! sudo systemctl is-enabled ly@tty1.service &>/dev/null; then
        step 1 "Enabling ly@tty1.service"
        sudo systemctl enable ly@tty1.service
    fi

    # Audio stack
    info "Installing audio..."
    install \
        pipewire \
        pipewire-pulse \
        pavucontrol \
        alsa-utils \
        sof-firmware
    success "Audio installed."

    # Docker group is configured in the devkit stage (docker is installed there).

    # yay (AUR helper) — built from source as the current (non-root) user.
    if ! command -v yay &>/dev/null; then
        info "Installing yay..."
        local yay_dir="$HOME/yay"
        if [[ ! -d "$yay_dir/.git" ]]; then
            git clone https://aur.archlinux.org/yay.git "$yay_dir"
        else
            git -C "$yay_dir" pull --ff-only
        fi
        (cd "$yay_dir" && makepkg -si --noconfirm)
    fi

    # AUR packages
    info "Installing AUR packages..."
    yay -S --needed --noconfirm \
        brave-bin \
        zed \
        visual-studio-code-bin

    success "Utilities installed."
}

# --- Developer kit ---
# Install development tools: mise, docker, toolchain, Zig, Dotnet, mobile & IDEs.
#
# @example
#   devkit
devkit() {
    info "Setting up developer kit..."

    sudo pacman -Syu

    install mise
    install docker docker-compose

    info "Configuring Docker..."
    step 1 "Enabling Docker service"
    sudo systemctl enable --now docker
    step 1 "Adding user to docker group"
    sudo usermod -aG docker "$USER"

    # System toolchain
    install clang gdb lldb cmake ninja valgrind
    install c3c

    step 1 "Installing Zig globally"
    mise use -g zig

    step 1 "Installing Dotnet globally"
    mise use -g dotnet

    # Mobile
    yay -S --needed --noconfirm jetbrains-toolbox
    install scrcpy

    # IDEs (AUR)
    yay -S --needed --noconfirm zed visual-studio-code-bin

    success "Developer kit installation complete."
}

# --- Fonts ---

# Install optional system fonts (Noto, Dejavu, Liberation).
#
# @example
#   fonts
fonts() {
    info "Installing fonts..."
    install \
        noto-fonts \
        noto-fonts-cjk \
        noto-fonts-emoji \
        noto-fonts-extra \
        ttf-dejavu \
        ttf-liberation
    success "Fonts installed."
}

# --- Main ---

readonly -A STAGE_MAP=(
    [system]=system
    [dotfiles]=dotfiles
    [polkit]=polkit
    [core]=core
    [drivers]=drivers
    [utilities]=utilities
    [devkit]=devkit
    [fonts]=fonts
)

usage() {
    cat <<EOF
Usage: $(basename "$0") [stage ...]

Stages: ${!STAGE_MAP[*]}

With no arguments, install stages run first, then config stages:
  core -> drivers -> utilities -> devkit -> fonts -> system -> dotfiles -> polkit
EOF
}

# Entry point: update the system, then run the requested stages (or all of them).
#
# @param {...string} stage - Stage names to run. Defaults to all stages.
main() {
    # makepkg (used by yay and the AUR steps) refuses to run as root.
    # Run as a normal user; this script escalates with sudo where needed.
    if ((EUID == 0)); then
        error "Do not run this script as root. Run it as a normal user (it uses sudo internally)."
        exit 1
    fi

    if (($# == 0)); then
        # Install stages first, then config stages.
        set -- core drivers utilities devkit fonts system dotfiles polkit
    fi

    for stage in "$@"; do
        if [[ "$stage" == "--help" || "$stage" == "-h" ]]; then
            usage
            exit 0
        fi
        if [[ -z "${STAGE_MAP[$stage]:-}" ]]; then
            error "Unknown stage: $stage"
            usage
            exit 1
        fi
    done

    # Full system update first
    info "Updating system..."
    sudo pacman -Syu --needed --noconfirm

    for stage in "$@"; do
        info ">>> Stage: $stage"
        "$stage"
    done

    success "All done."
}

main "$@"
