#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias ll='ls -alF --color=auto'
alias grep='grep --color=auto'

git_push() {
    git status || return 1

    read -r -p "Commit and push? (y/N) " confirm
    [[ "$confirm" == "y" ]] || return 0

    git add . || return 1

    read -r -p "Commit message: " message
    [[ -n "$message" ]] || {
        echo "Error: commit message cannot be empty."
        return 1
    }

    git commit -m "$message" &&
        git push origin main &&
        echo "==> Push complete"
}

# --- Alias ---
#
alias up="sudo pacman -Syu"
tldrv() {
    tldr "$@" | less -FRX
}
alias src="source ~/.bashrc"

PS1='[\u@\h \W]\$ '
eval "$(mise activate bash)"
export PATH="$HOME/.local/bin:$PATH"
alias tealdeer='tldr'
export PATH="$HOME/.local/bin:$PATH"

# opencode
export PATH="$HOME/.opencode/bin:$PATH"

#   --- VTR (View Tree)---
#   Print recursively list file and directories
#   @param {string} [dir=.] - the directory to display
#   @param {string} [prefix=""] - The indentation prefix used for recursion.
#   @returns {void}
# vtr() {
#     local dir="${1:-.}"
#     local prefix="${2:-}"

#     local paths=("$dir"/*)
#     local filtered=()

#     for path in "${paths[@]}"; do
#         [[ -e "$path" ]] && filtered+=("$path")
#     done

#     local total=${#filtered[@]}
#     local i=0

#     for path in "${filtered[@]}"; do
#         ((i++))
#         if (( i == total )); then
#             printf '%s└── %s\n' "$prefix" "${path##*/}"
#             [[ -d "$path" ]] && vtr "$path" "${prefix}    "
#         else
#             printf '%s├── %s\n' "$prefix" "${path##*/}"
#             [[ -d "$path" ]] && vtr "$path" "${prefix}│   "
#         fi
#     done
# }

vtr() {
    local current_path="${1:-.}"
    local max_depth="${2:-}"
    local walk_dir

    walk_dir() {
        local path="$1"
        local prefix="$2"
        local depth="$3"
        local entry 
        local entries=()
        local i count connector next_prefix

        if [[ -n "$max_depth" ]] && (( depth >= max_depth )); then
            return
        fi

        shopt -s nullglob dotglob
        entries=("$path"/*)
        shopt -u nullglob dotglob
    
        if ((${#entries[@]})); then
            while IFS= read -r entry; do
                sorted+=("$entry")
            done < <(printf '%s\n' "${entries[@]}" | sort)
        fi
    }
}


