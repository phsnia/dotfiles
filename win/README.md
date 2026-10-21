# Windows dotfiles

Run `bootstrap.ps1` once; it relaunches itself elevated and symlinks your
PowerShell profile to the repo:

```
.\bootstrap.ps1
```

That links `$PROFILE` (whatever host and scope you launch it from — pwsh or
Windows PowerShell, current user) to `Microsoft.PowerShell_profile.ps1` in this
directory. It force-replaces whatever is already there.

Bootstrap only initializes the tooling: scoop (with git) and winget. It also
runs the remaining stages — Windows Update (scan, confirm, install), the
ReviOS debloat, driver management and the profile link. Install your actual
software afterwards with:

```
.\install-software.ps1
```

It records every managed package (installed, already present or failed) to
`~\.dotfiles\software.state.json`.

Reload afterwards with:

```
src_profile
```

## Layout

```
win/
├── README.md                         # This file
├── ARCHITECTURE.md                   # Design and overview notes
├── bootstrap.ps1                     # Elevates and symlinks $PROFILE → repo
├── install-software.ps1              # Scoop/winget packages + installers (run after bootstrap)
├── Microsoft.PowerShell_profile.ps1  # The linked PowerShell profile
├── ame-cli.ps1                       # AME CLI helper script
├── specs/
│   ├── simple-echo-logging.md        # Spec: simple echo logging
│   ├── docs/
│   │   └── window_defeneder_docs.txt
│   └── plans/
│       ├── parallel-update-download.md  # Plan: parallel update downloads (superseded)
│       ├── simple-windows-update.md     # Plan: simple Windows Update stage
│       └── turn-off-defender.md         # Plan: turn off Windows Defender
└── tests/
    ├── Bootstrap.Tests.ps1           # Pester tests for every bootstrap stage (incl. debloat)
    ├── Defender.Tests.ps1            # Pester tests for the Defender helpers
    └── InstallSoftware.Tests.ps1     # Pester tests for software install + state file
```

## Turning Defender off

Windows Defender is turned off before the ReviOS playbook runs — the playbook
refuses to apply while it is on. `bootstrap.ps1` does everything the platform
allows and hands the rest to you: while Tamper Protection is on, the platform
refuses every scripted change, so the stage opens Windows Security and waits
until the toggles are off.

Windows Security > Virus & threat protection > Manage settings is where the
toggles live — turn **Tamper protection** off first, then **Real-time
protection**. The stage re-checks after each round and stops with an error
when a toggle is still on.
