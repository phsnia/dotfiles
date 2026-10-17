alias ll="ls -alF --color=auto"
alias src="source ~/.bashrc"
function fput() {
    git status &&
    read -r -p "Commit and push? (y/N) " confirm &&
    [[ "$confirm" == "y" ]] &&
    git add . &&
    read -r -p "Commit message: " message &&
    git commit -m "$message" &&
    git push origin main
}
