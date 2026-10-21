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
runs the remaining stages — a Windows Update **check** (scan and report only,
it never installs: pending updates are opened in `ms-settings:windowsupdate`
for you, and `-SkipUpdateCheck` skips the scan), the ReviOS debloat, driver
management and the profile link. Install your actual software afterwards
with:

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
├── bootstrap.ps1                     # Elevates, checks Windows Update, symlinks $PROFILE → repo
├── install-software.ps1              # Scoop/winget packages + installers (run after bootstrap)
├── Microsoft.PowerShell_profile.ps1  # The linked PowerShell profile
├── ame-cli.ps1                       # AME CLI helper script
├── lib/
│   └── common.ps1                    # Shared helpers (Get-RemoteFile, Test-Artifact)
├── specs/
│   ├── simple-echo-logging.md        # Spec: simple echo logging
│   ├── docs/
│   │   └── window_defeneder_docs.txt
│   └── plans/
│       ├── parallel-update-download.md  # Plan: parallel update downloads (superseded)
│       ├── simple-windows-update.md     # Plan: simple Windows Update stage (superseded)
│       ├── turn-off-defender.md         # Plan: turn off Windows Defender
│       └── verify-windows-update.md     # Plan: Windows Update check without install
└── tests/
    ├── Bootstrap.Tests.ps1           # Pester tests for every bootstrap stage (incl. debloat)
    ├── Defender.Tests.ps1            # Pester tests for the Defender helpers
    └── InstallSoftware.Tests.ps1     # Pester tests for software install + state file
```

## Turning Defender off

Windows Defender is turned off before the ReviOS playbook runs — the playbook
refuses to apply while it is on. The stage is deliberately simple and
manual: it reads the four toggles, prints what is still on and opens Windows
Security for you. It never writes to the platform — Tamper Protection
refuses every scripted change anyway.

Windows Security > Virus & threat protection > Manage settings is where the
toggles live — turn **Tamper protection** off first, then **Real-time
protection**. The stage re-checks after each round (max 3, one when
unattended) and stops with an error when a toggle is still on.
