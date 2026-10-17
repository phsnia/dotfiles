# ssh config

Shared ssh configuration. The directory is symlinked to `~/.config/ssh` by
`linux/arch/bootstrap.sh` (the `dotfiles` stage).

OpenSSH has **no** XDG support — it only ever reads `~/.ssh/config`. That is
why the stage also writes a one-line shim:

```
# ~/.ssh/config
Include ~/.config/ssh/config
```

So the chain is `~/.ssh/config` → `~/.config/ssh/config` → `~/.config/ssh/local`.
The shim is only created when `~/.ssh/config` does not exist; if you already
have one, the stage warns and leaves it alone instead of clobbering it.

## Files

| File            | Tracked | Purpose                                        |
| --------------- | ------- | ---------------------------------------------- |
| `config`        | yes     | sane `Host *` defaults, includes `local`        |
| `local.example` | yes     | template for `local`                            |
| `README.md`     | yes     | this file                                       |
| `local`         | **no**  | your hosts and identities, mode `600`           |

Keys, `known_hosts` and `authorized_keys` stay in `~/.ssh` and are never
touched by the dotfiles stage.

## Setup

```bash
# 1. a key, once
ssh-keygen -t ed25519 -C "tuanhphu2004@gmail.com"

# 2. the personal include
cd ~/.config/ssh
cp local.example local
chmod 600 local
$EDITOR local

# 3. agent (Arch: one service, all shells)
systemctl --user enable --now ssh-agent
ssh-add ~/.ssh/id_ed25519
```

Then paste `~/.ssh/id_ed25519.pub` into GitHub → Settings → SSH and GPG keys.

## Permissions

OpenSSH refuses to use files that are too open:

| Path                  | Mode |
| --------------------- | ---- |
| `~/.ssh`              | 700  |
| `~/.ssh/*` (keys)     | 600  |
| `~/.ssh/config`       | 600  |
| `~/.config/ssh/config`| 644  |
| `~/.config/ssh/local` | 600  |

Private keys must be `600`; a `644` key makes `ssh` complain and refuse.

## Verify

```bash
ssh -G github.com | grep -E '^(user|identityfile)'
ssh -G vps | grep -E '^(hostname|port|user)'
```

`ssh -G` prints the effective configuration for a host without connecting, so
it is the fastest way to prove the shim, the include and `local` are all being
read. Outright syntax errors show up as `Bad configuration option: ...` on
stderr — add `2>&1` to see them.

## Known hosts

`~/.ssh/known_hosts` is not tracked: host keys are machine- and host-specific.
Verify a fingerprint before accepting it, since trusting the wrong one is the
whole point of the file.

## Rotate a key

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_new -C "tuanhphu2004@gmail.com"
ssh-copy-id -i ~/.ssh/id_ed25519_new.pub vps    # or add it in GitHub
# point IdentityFile at the new key in local, verify a login, then:
rm ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
```

Remove the old public key from the server/GitHub as well.
