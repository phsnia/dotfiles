#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias ll='ls -alF --color=auto'
alias grep='grep --color=auto'

# alias 
alias up="sudo pacman -Syu"

function fput() {
    git status &&
    read -r -p "Commit and push? (y/N) " confirm &&
    [[ "$confirm" == "y" ]] &&
    git add . &&
    read -r -p "Commit message: " message &&
    git commit -m "$message" &&
    git push origin main
    echo "==> Push file"
}

tldrv() {
    tldr "$@" | less -FRX
}

alias src="source ~/.bashrc"

PS1='[\u@\h \W]\$ '
eval "$(mise activate bash)"
export PATH="$HOME/.local/bin:$PATH"
alias tealdeer='tldr'
export PATH="$HOME/.local/bin:$PATH"
