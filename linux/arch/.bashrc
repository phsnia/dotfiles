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

#   --- VTR (View Tree) ---
#   Recursively print files and directories as a tree.
#   @param {string} [dir=.]     - the directory to display
#   @param {number} [max_depth] - maximum recursion depth
#   @returns {void}
vtr() {
    local current_path="${1:-.}"
    local max_depth="${2:-}"

    walk_dir() {
        local current_path="$1"
        local prefix="$2"
        local depth="$3"

        # IF maximum depth has been reached: RETURN
        if [[ -n "$max_depth" ]] && (( depth >= max_depth )); then
            return
        fi

        # entries = get all entries inside current_path (including dotfiles)
        local -a entries=() hidden=() visible=()
        local entry i count connector next_prefix

        shopt -s nullglob dotglob
        entries=("$current_path"/*)
        shopt -u nullglob dotglob

        # SORT entries in a consistent order: dotfiles first, then the rest.
        for entry in "${entries[@]}"; do
            if [[ "${entry##*/}" == .* ]]; then
                hidden+=("$entry")
            else
                visible+=("$entry")
            fi
        done

        if ((${#hidden[@]} > 1)); then
            mapfile -t hidden < <(printf '%s\n' "${hidden[@]}" | sort)
        fi
        if ((${#visible[@]} > 1)); then
            mapfile -t visible < <(printf '%s\n' "${visible[@]}" | sort)
        fi
        entries=("${hidden[@]}" "${visible[@]}")

        # FOR i = 0 TO length(entries) - 1
        count=${#entries[@]}
        for ((i = 0; i < count; i++)); do
            entry="${entries[i]}"

            # is_last?
            if (( i == count - 1 )); then
                connector="└── "
                next_prefix="$prefix    "
            else
                connector="├── "
                next_prefix="$prefix│   "
            fi

            # PRINT prefix + connector + entry.name
            printf '%s%s%s\n' "$prefix" "$connector" "${entry##*/}"

            # IF entry is a directory: walk_dir(entry.path, ...)
            # (skip symlinks so a link cycle cannot recurse forever)
            if [[ -d "$entry" && ! -L "$entry" ]]; then
                walk_dir "$entry" "$next_prefix" "$((depth + 1))"
            fi
        done
    }

    # PRINT root directory name, then walk it.
    local root="${current_path%/}"
    [[ -z "$root" ]] && root="/"
    printf '%s\n' "$root"

    walk_dir "$current_path" "" 0
}
