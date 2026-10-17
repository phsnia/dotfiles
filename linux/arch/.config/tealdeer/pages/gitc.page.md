# gitc

> Display a Git cheat sheet for common commands.

- Show this cheat sheet:

`gitc`

- Setup: Show Git version:

`git --version`

- Setup: Set global username:

`git config --global user.name "Your Name"`

- Setup: Set global email:

`git config --global user.email "you@example.com"`

- Setup: List configuration:

`git config --list`

- Setup: Initialize a repository:

`git init`

- Setup: Clone a repository:

`git clone {{url}}`

- Status: Show working tree status:

`git status`

- Status: Show concise status:

`git status --short`

- Status: Show commit history:

`git log`

- Status: Show compact history:

`git log --oneline`

- Status: Show graph of branches:

`git log --oneline --graph --decorate --all`

- Status: Show changes not staged:

`git diff`

- Status: Show staged changes:

`git diff --staged`

- Status: Show a commit:

`git show {{commit}}`

- Commit: Stage a file:

`git add {{file}}`

- Commit: Stage all changes:

`git add .`

- Commit: Stage interactively:

`git add -p`

- Commit: Commit staged changes:

`git commit -m "message"`

- Commit: Stage tracked changes and commit:

`git commit -am "message"`

- Commit: Amend the latest commit:

`git commit --amend`

- Commit: Amend without changing the message:

`git commit --amend --no-edit`

- Branch: List local branches:

`git branch`

- Branch: List all branches:

`git branch -a`

- Branch: Create a branch:

`git branch {{branch}}`

- Branch: Switch branches:

`git switch {{branch}}`

- Branch: Create and switch to a branch:

`git switch -c {{branch}}`

- Branch: Rename the current branch:

`git branch -m {{new-name}}`

- Branch: Delete a merged branch:

`git branch -d {{branch}}`

- Branch: Force-delete a branch:

`git branch -D {{branch}}`

- Merge: Merge a branch into the current branch:

`git merge {{branch}}`

- Merge: Continue after resolving conflicts:

`git add {{resolved-files}} && git merge --continue`

- Merge: Abort a merge:

`git merge --abort`

- Rebase: Rebase onto another branch:

`git rebase {{branch}}`

- Rebase: Continue a rebase:

`git rebase --continue`

- Rebase: Abort a rebase:

`git rebase --abort`

- Rebase: Rebase interactively over the last commits:

`git rebase -i HEAD~{{n}}`

- Remote: List remotes:

`git remote -v`

- Remote: Add a remote:

`git remote add origin {{url}}`

- Remote: Change a remote URL:

`git remote set-url origin {{url}}`

- Remote: Fetch remote changes:

`git fetch`

- Remote: Fetch and prune deleted remote branches:

`git fetch --prune`

- Remote: Pull changes:

`git pull`

- Remote: Pull using rebase:

`git pull --rebase`

- Remote: Push the current branch:

`git push`

- Remote: Push and set upstream:

`git push -u origin {{branch}}`

- Remote: Delete a remote branch:

`git push origin --delete {{branch}}`

- Undo: Unstage a file:

`git restore --staged {{file}}`

- Undo: Discard unstaged changes to a file:

`git restore {{file}}`

- Undo: Restore a file from a commit:

`git restore --source {{commit}} -- {{file}}`

- Undo: Revert a commit safely:

`git revert {{commit}}`

- Undo: Reset to the previous commit, keeping changes staged:

`git reset --soft HEAD~1`

- Undo: Reset to the previous commit, keeping changes unstaged:

`git reset HEAD~1`

- Undo: Reset and discard local changes:

`git reset --hard {{commit}}`

- Stash: Stash tracked changes:

`git stash`

- Stash: Stash including untracked files:

`git stash -u`

- Stash: List stashes:

`git stash list`

- Stash: Apply the latest stash and keep it:

`git stash apply`

- Stash: Apply and remove the latest stash:

`git stash pop`

- Stash: Delete the latest stash:

`git stash drop`

- Tags: List tags:

`git tag`

- Tags: Create a tag:

`git tag {{tag}}`

- Tags: Create an annotated tag:

`git tag -a {{tag}} -m "message"`

- Tags: Push a tag:

`git push origin {{tag}}`

- Tags: Push all tags:

`git push --tags`

- Tags: Delete a local tag:

`git tag -d {{tag}}`

- Tags: Delete a remote tag:

`git push origin --delete {{tag}}`

- File: Show changed files:

`git diff --name-only`

- File: Show tracked files:

`git ls-files`

- File: Stop tracking a file but keep it locally:

`git rm --cached {{file}}`

- File: Rename or move a tracked file:

`git mv {{old-path}} {{new-path}}`

- File: Delete a tracked file:

`git rm {{file}}`

- File: Show ignored files:

`git status --ignored`

- Search: Search commit history for a message:

`git log --grep="{{text}}"`

- Search: Find commits that changed a file:

`git log -- {{file}}`

- Search: Show who changed each line:

`git blame {{file}}`

- Search: Search tracked files for text:

`git grep "{{text}}"`

- Search: Find which commit introduced a change:

`git log -S"{{text}}" --all`

- Recovery: Show recent HEAD movements:

`git reflog`

- Recovery: Recover a lost commit using its hash:

`git branch recovery {{commit}}`

- Recovery: Check repository integrity:

`git fsck`

- Recovery: Remove stale remote-tracking branches:

`git remote prune origin`

- Shortcut: Show the current branch:

`git branch --show-current`

- Shortcut: Show the last commit:

`git log -1 --oneline`

- Shortcut: Compare two branches:

`git diff {{branch1}}..{{branch2}}`

- Shortcut: Show commits not yet pushed:

`git log @{u}..HEAD --oneline`

- Shortcut: Show commits on the remote but not local:

`git log HEAD..@{u} --oneline`

- Shortcut: Create a branch from another branch:

`git switch -c {{new-branch}} {{start-point}}`

- Shortcut: Preview files that would be deleted by clean:

`git clean -nd`

- Shortcut: Remove untracked files permanently:

`git clean -fd`
