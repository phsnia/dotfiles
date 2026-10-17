# git config

Shared git configuration, symlinked to `~/.config/git` by
`linux/arch/bootstrap.sh` (the `dotfiles` stage).

Git reads `$XDG_CONFIG_HOME/git/config`, so no `~/.gitconfig` is involved.
If a `~/.gitconfig` ever appears it is read *after* this file and wins on
conflicts — delete it if things stop behaving as documented here.

Personal data and secrets never live in this repo: `local` (identity) and
`.env` (token) are both gitignored and only exist on the machine.

## Files

| File           | Tracked | Purpose                                            |
| -------------- | ------- | -------------------------------------------------- |
| `config`       | yes     | defaults, credential helper, `include` of `local`   |
| `.env.example` | yes     | template for `.env` (placeholder token only)        |
| `README.md`    | yes     | this file                                           |
| `local`        | **no**  | `[user]` identity, edited by hand, mode `600`       |
| `.env`         | **no**  | credentials for git's `store` helper, mode `600`    |

## Setup

Identity — `local` is a plain git config include:

```ini
[user]
	name = phsnia
	email = tuanhphu2004@gmail.com
```

```bash
chmod 600 ~/.config/git/local
```

Credentials — `.env` is a line per host, in `store` format:

```
https://<username>:<token>@github.com
```

```bash
cp .env.example .env     # then set a real token
chmod 600 .env
```

Write that line without pasting the token into a shell history by letting git
do it:

```bash
printf 'protocol=https\nhost=github.com\nusername=phsnia\npassword=ghp_xxx\n\n' \
	| git credential approve
```

`git credential approve` hands the values to the configured helper, which
appends the line to `.env` for you.

## How it works

`config` includes the hand-maintained identity file:

```ini
[include]
	path = local
```

and points git's built-in `store` helper at `.env`:

```ini
[credential]
	helper = store --file=$HOME/.config/git/.env
```

`$HOME` (not `~`) is required: git runs credential helpers through a shell,
so `$HOME` expands, while a `~` in the middle of a word does not.

The helper is intentionally *unscoped* here. Unlike a custom helper, `store`
can only answer for hosts that have a line in the file, so a credential for
`github.com` is never offered to any other host.

## Verify

```bash
git config --get user.email                  # -> from local
git config --show-origin --get user.email
printf 'protocol=https\nhost=github.com\n\n' | git credential fill
```

The last command echoes the username and token from `.env`. If it fails with
`could not read Username`, `.env` is missing, unreadable, or the line's host
does not match.

## Rotate / revoke

Editing the token in `.env` is enough — nothing caches it.

```bash
$EDITOR ~/.config/git/.env
```

Revoke the old token in GitHub → Settings → Developer settings →
Personal access tokens. If a token is ever committed, revoke it first —
rewriting history does not un-leak it.

## Caveats

- `.env` is plaintext, like every `store` setup. `chmod 600` and a private
  machine are the only protections; it is gitignored, so it never lands in
  this repo.
- For a keyring-backed helper instead, install `libsecret` and use
  `git config credential.helper libsecret`.
