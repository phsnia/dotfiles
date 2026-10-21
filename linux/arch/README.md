# Arch Linux

Dotfiles and installer for an Arch Linux (i3 / Xorg) setup.

`bootstrap.sh` installs packages and configures the system, then links the
configs in `.config/` into `~/.config`. See `ARCHITECTURE.md` for the flow.

## Structure

```text
arch/
├── .bashrc                 # shell startup file -> ~/.bashrc
├── .gitignore              # ignores machine-local secrets and state
├── ARCHITECTURE.md         # mermaid flowchart of bootstrap.sh
├── bootstrap.sh            # installer / configurator
├── README.md
└── .config/                # XDG configs -> ~/.config
    ├── alacritty/
    │   └── alacritty.toml
    ├── git/
    │   ├── .env.example
    │   ├── config
    │   └── README.md
    ├── i3/
    │   └── config
    ├── ssh/
    │   ├── config
    │   ├── local.example
    │   └── README.md
    ├── tealdeer/
    │   ├── config.toml
    │   └── pages/
    │       ├── cheat.page.md
    │       ├── gitc.page.md
    │       └── sshc.page.md
    └── tmux/
        └── tmux.conf
```

## Scripts

| File | Purpose |
| --- | --- |
| `bootstrap.sh` | Install packages and link dotfiles. Run as a normal user (it uses `sudo` internally). |
| `ARCHITECTURE.md` | Mermaid flowchart of `bootstrap.sh`. |

```bash
./bootstrap.sh                 # run all stages
./bootstrap.sh core fonts      # run selected stages
./bootstrap.sh --help
```

Stages: `core`, `drivers`, `utilities`, `devkit`, `fonts`, `system`, `dotfiles`, `polkit`.

## Configs

| Directory | Purpose |
| --- | --- |
| `alacritty/` | Terminal emulator |
| `git/` | git config and credential setup (see `git/README.md`) |
| `i3/` | Window manager |
| `ssh/` | ssh config and include shim (see `ssh/README.md`) |
| `tealdeer/` | tldr client config and custom pages |
| `tmux/` | Terminal multiplexer |

## Machine-local (gitignored)

These never leave the machine:

- `.config/git/.env` — git credentials (template: `.env.example`)
- `.config/git/local` — git identity
- `.config/ssh/local` — ssh hosts and identities (template: `local.example`)

The `dotfiles` stage also writes a `~/.ssh/config` include shim and seeds
`~/.config/ssh/local` from `local.example` when missing.
