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
runs the remaining stages — a Windows Update **stage** first (it scans,
installs the pending updates and scans again until no update package is left;
a pending reboot ends the round and the remaining updates are installed by the
next run, `-SkipUpdateCheck` skips the stage), then the ReviOS debloat, driver
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
├── bootstrap.ps1                     # Elevates, installs Windows updates, symlinks $PROFILE → repo
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
│       ├── fix-defender-toggle-detection.md # Plan: fix the Defender toggle detection
│       ├── merge-update-into-bootstrap.md # Plan: merge the update installer into bootstrap
│       ├── parallel-update-download.md  # Plan: parallel update downloads (superseded)
│       ├── simple-defender-check.md     # Plan: simple Windows Defender check
│       ├── simple-windows-update.md     # Plan: simple Windows Update stage (superseded)
│       ├── simplify-bootstrap-code.md   # Plan: core/support split of bootstrap.ps1
│       ├── simplify-bootstrap-helpers.md # Plan: merge the one-caller bootstrap helpers
│       ├── turn-off-defender.md         # Plan: turn off Windows Defender
│       └── verify-windows-update.md     # Plan: Windows Update check without install (superseded)
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
protection**, **Microsoft Defender Antivirus cloud protection** and
**Automatically send sample files**. The stage waits for you to press Enter,
checks once more and stops with an error when a toggle is still on. With
`-Unattended` it only reports: no window is opened and the debloat is
blocked.
