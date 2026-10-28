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
readonly PACKAGES_FILE="$DOTFILES_DIR/packages.txt"

# Polkit mount rule is written for this user (override with POLKIT_USER).
readonly POLKIT_USER="${POLKIT_USER:-phng}"

# External fonts fetched from upstream (not in repos)
readonly FONT_DIR_BASE="/usr/local/share/fonts"

# Format: "<family>/<filename>|<url>"
# family -> installed to $FONT_DIR_BASE/<family>
readonly -a EXTRA_FONTS=(
    "comic-mono/ComicMono.ttf|https://dtinth.github.io/comic-mono-font/ComicMono.ttf"
    "comic-mono/ComicMono-Bold.ttf|https://dtinth.github.io/comic-mono-font/ComicMono-Bold.ttf"
)

# Colors & log helpers

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly RESET='\033[0m'

# Log helpers
#
# Level-based indentation: each level adds one leading tab.
#   info 0 "msg"   -> ==> msg
#   info 1 "msg"   -> 	==> msg
#   info "msg"     -> ==> msg   (level defaults to 0)
#
# Low-level log writer shared by the log helpers below.
#
# @param {string} color   - ANSI color escape.
# @param {string} arrow   - Arrow prefix (==> or ->).
# @param {number} [level] - Optional indentation level.
# @param {...string} msg  - Message text.
# @example
#   _log "$BLUE" "==>" 1 "indented"
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

# Log an info line (blue ==>).
#
# @param {number} [level] - Optional indentation level.
# @param {...string} msg  - Message text.
# @example
#   info "Installing..."
info()   { _log "${BLUE}"  "==>" "$@"; }

# Log a success line (green ==>).
#
# @param {number} [level] - Optional indentation level.
# @param {...string} msg  - Message text.
# @example
#   success "Done."
success() { _log "${GREEN}" "==>" "$@"; }

# Log a warning line (yellow ==>).
#
# @param {number} [level] - Optional indentation level.
# @param {...string} msg  - Message text.
# @example
#   warn "Careful."
warn()   { _log "${YELLOW}" "==>" "$@"; }

# Log an error line (red ==>, written to stderr).
#
# @param {number} [level] - Optional indentation level.
# @param {...string} msg  - Message text.
# @example
#   error "Something failed."
error()  { _log "${RED}"   "==>" "$@" >&2; }

# Log a sub-step line (blue ->).
#
# @param {number} [level] - Optional indentation level.
# @param {...string} msg  - Message text.
# @example
#   step 1 "Enabling ly@tty1.service"
step() {
    _log "${BLUE}" "->" "$@"
}

# Helpers

# Install packages that are not already installed.
#
# @param {...string} pkg - Package names to install.
# @example
#   install_packages git curl neovim
install_packages() {
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

# Print packages for a stage and manager from packages.txt.
#
# @param {string} stage   - Stage name (core, drivers, utilities, ...).
# @param {string} manager - Package manager (pacman, aur, mise).
# @example
#   packages_for core pacman
packages_for() {
    local stage="$1" manager="$2"
    awk -v stage="$stage" -v manager="$manager" '
        /^[[:space:]]*(#|$)/ { next }
        $1 == stage && $2 == manager { print $3 }
    ' "$PACKAGES_FILE"
}

# Install a stage's packages for one manager, using packages.txt.
#
# @param {string} stage            - Stage name.
# @param {string} [manager=pacman] - Package manager (pacman, aur, mise).
# @example
#   install_stage_packages utilities
#   install_stage_packages devkit aur
install_stage_packages() {
    local stage="$1" manager="${2:-pacman}"
    local -a pkgs=()

    mapfile -t pkgs < <(packages_for "$stage" "$manager")
    ((${#pkgs[@]})) || return 0

    case "$manager" in
        pacman) install_packages "${pkgs[@]}" ;;
        aur)    yay -S --needed --noconfirm "${pkgs[@]}" ;;
        mise)   mise use -g "${pkgs[@]}" ;;
        *)
            error "Unknown package manager for stage $stage: $manager"
            exit 1
            ;;
    esac
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

# Symlink $1 to $2, backing up an existing real path to "$2.bak" first.
# A plain `ln -sfn` refuses to replace an existing directory.
#
# @param {string} src  - Source path to link from.
# @param {string} dest - Destination link path.
# @example
#   link_config "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
link_config() {
    local src="$1" dest="$2"

    if [[ -e "$dest" && ! -L "$dest" ]]; then
        step 1 "Backing up existing $dest -> $dest.bak"
        mv "$dest" "$dest.bak"
    fi

    ln -sTfn "$src" "$dest"
}

# Symlink dotfiles config directories and .bashrc into $HOME.
#
# @example
#   dotfiles
dotfiles() {
    info "Linking dotfiles..."

    link_config "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"

    mkdir -p "$CONFIG_DIR"
    local -a CONFIGS=(
        i3
        alacritty
        git
        tmux
        ssh
    )
    for config in "${CONFIGS[@]}"; do
        link_config "$DOTFILES_CONFIG/$config" "$CONFIG_DIR/$config"
    done

    # ~/.ssh cannot be replaced wholesale (private keys live there), and ssh
    # has no XDG support, so point ~/.ssh/config at the linked config with a
    # one-line include instead of symlinking the directory.
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    local ssh_include="Include ~/.config/ssh/config"
    if [[ ! -e "$HOME/.ssh/config" ]]; then
        step 1 "Creating ~/.ssh/config shim for ~/.config/ssh/config"
        printf '%s\n' "$ssh_include" >"$HOME/.ssh/config"
        chmod 600 "$HOME/.ssh/config"
    elif ! grep -qF '~/.config/ssh/config' "$HOME/.ssh/config"; then
        warn "~/.ssh/config exists without the dotfiles include; add:"
        warn "  $ssh_include"
    fi

    # Seed the gitignored ssh/local so the include above always resolves.
    if [[ ! -f "$CONFIG_DIR/ssh/local" && -f "$CONFIG_DIR/ssh/local.example" ]]; then
        step 1 "Seeding ~/.config/ssh/local from local.example"
        install -m 600 "$CONFIG_DIR/ssh/local.example" "$CONFIG_DIR/ssh/local"
    fi

    success "Dotfiles linked."
}

# --- Polkit ---

# Install polkit/udiskie and write the udiskie mount polkit rule for $POLKIT_USER.
#
# @example
#   polkit
polkit() {
    info "Installing polkit / udiskie and configuring mount rules..."

    install_stage_packages polkit
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
    install_stage_packages core
    success "Core packages installed."
}

# --- Graphics drivers ---

# Install graphics drivers for Intel, AMD, NVIDIA and Nouveau GPUs.
#
# @example
#   drivers
drivers() {
    info "Installing graphics drivers..."
    install_stage_packages drivers
    success "Graphics drivers installed."
}

# --- Utilities ---

# Install window manager, terminal multiplexer, Xorg, audio stack, yay (AUR
# helper) and AUR apps. Enables the ly display manager.
#
# @example
#   utilities
utilities() {
    info "Installing utilities, window manager and audio..."

    install_stage_packages utilities

    # Configure ly display manager
    info "Configuring ly..."
    if ! sudo systemctl is-enabled ly@tty1.service &>/dev/null; then
        step 1 "Enabling ly@tty1.service"
        sudo systemctl enable ly@tty1.service
    fi

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
    install_stage_packages utilities aur

    success "Utilities installed."
}

# --- Developer kit ---
# Install development tools: mise, docker, toolchain, Zig, Dotnet, mobile & IDEs.
#
# @example
#   devkit
devkit() {
    info "Setting up developer kit..."

    install_stage_packages devkit

    info "Configuring Docker..."
    step 1 "Enabling Docker service"
    sudo systemctl enable --now docker
    step 1 "Adding user to docker group"
    sudo usermod -aG docker "$USER"

    step 1 "Installing global mise tools"
    install_stage_packages devkit mise

    # AUR packages
    info "Installing AUR packages..."
    install_stage_packages devkit aur

    success "Developer kit installation complete."
}

# --- Fonts ---

# Install optional system fonts (Noto, Dejavu, Liberation, + any EXTRA_FONTS).
#
# @example
#   fonts
fonts() {
    info "Installing fonts..."
    install_stage_packages fonts

    local entry relpath url family filename target_dir
    local -A created_dirs=()

    for entry in "${EXTRA_FONTS[@]}"; do
        IFS='|' read -r relpath url <<< "$entry"
        family="${relpath%%/*}"
        filename="${relpath##*/}"
        target_dir="$FONT_DIR_BASE/$family"

        if [[ -z "${created_dirs[$target_dir]:-}" ]]; then
            step 1 "Ensuring $target_dir exists"
            sudo install -d -m 755 "$target_dir"
            created_dirs[$target_dir]=1
        fi

        if [[ ! -f "$target_dir/$filename" ]]; then
            step 1 "Downloading $filename ($family)"
            curl -fsSL "$url" | sudo tee "$target_dir/$filename" >/dev/null || {
                error "Failed to download $filename"
                return 1
            }
            sudo chmod 644 "$target_dir/$filename"
        else
            step 1 "$filename ($family) already installed, skipping"
        fi
    done

    step 1 "Refreshing font cache"
    sudo fc-cache -f "$FONT_DIR_BASE"

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

# Print script usage and the list of available stages.
#
# @example
#   usage
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
# @example
#   main core fonts
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

    if [[ ! -f "$PACKAGES_FILE" ]]; then
        error "Missing package list: $PACKAGES_FILE"
        exit 1
    fi

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
