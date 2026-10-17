readonly CONFIG_DIR="$HOME/.config"
readonly DOTFILES_CONFIG="$dotfiles/.config"
config() {
    # --- Time ---
    sudo timedatectl set-timezone Asia/Ho_Chi_Minh
    sudo timedatectl set-ntp true

    # --- Dotfiles ---
    local dotfiles
    dotfiles="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

    ln -sfn "$dotfiles/.bashrc" "$HOME/.bashrc"

    # rm -rf -- "$HOME/.config"
    CONFIGS=(
        i3 
        alacritty
    )

    for config in "${CONFIGS[@]}"; do
        ln -sTfn "$DOTFILES_CONFIG/$config" "$CONFIG_DIR/$config"
    done
}
config
