# Windows dotfiles

Run `bootstrap.ps1` once; it relaunches itself elevated and symlinks your
PowerShell profile to the repo:

```
.\bootstrap.ps1
```

That links `$PROFILE` (whatever host and scope you launch it from — pwsh or
Windows PowerShell, current user) to `Microsoft.PowerShell_profile.ps1` in this
directory. It force-replaces whatever is already there.

Bootstrap only initializes the tooling: scoop (with git) and winget. Install
your actual software afterwards with:

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
├── Debloat.Tests.ps1                 # Pester tests for debloat logic
├── ame-cli.ps1                       # AME CLI helper script
├── specs/
│   └── simple-echo-logging.md        # Spec: simple echo logging
└── tests/
    ├── Bootstrap.Tests.ps1           # Pester tests for every bootstrap stage
    └── InstallSoftware.Tests.ps1     # Pester tests for software install + state file
```