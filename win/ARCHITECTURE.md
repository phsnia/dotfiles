# Windows bootstrap architecture

Every stage component in `bootstrap.ps1` follows the same contract:

```mermaid
flowchart TD
    IN([Component called]) --> V{Verify: is the work already done?}

    V -- "Yes" --> S[Skip - log 'already done']
    S --> OUT([Component returns])

    V -- "No" --> E[Execute the work]
    E -- Success --> DONE[State now satisfies the verify check]
    DONE --> OUT

    E -- Failure --> H{Error handled INSIDE the component}

    H -- "best effort" --> W[Log WARN - continue to next stage]
    W --> OUT
    H -- "critical" --> R[Log ERROR - rethrow]
    R --> MAIN[main catches: save recovery state, stop]
```

- **Verify first** — each component checks its own end state (marker file,
  package actually installed, device status, symlink target, update scan…).
  Already done → log and return without touching anything.
- **Self-repair where cheap** — `Initialize-Winget` does not fail outright
  when `winget` is missing: `Repair-Winget` first asks the Microsoft Store
  to run an update scan (App Installer arrives from the Store), then falls
  back to downloading and installing the latest winget-cli `.msixbundle`
  with its dependency packages (a zip on recent releases, standalone
  `.appx` on older ones). Only when both routes fail does the stage
  rethrow.
- **Interactive prerequisites** — when a step needs a human (Tamper
  Protection, the four Windows Security toggles), the stage names the
  toggle that is still on, waits for confirmation and re-checks before
  continuing. The ReviOS CLI is never started while a toggle is on, so it
  cannot hang on its own "press any key" loop.
- **Error handling inside** — each component wraps its work in `try/catch`
  itself. Best-effort components (updates, drivers) log a `WARN` and let the
  bootstrap continue; critical components (scoop init, winget init, debloat
  apply, profile link) log `ERROR` and rethrow so `main` can save the
  recovery state and stop.
- **Downloads overlap, installs do not** — `Update-Windows` fetches pending
  content with up to `UpdateDownloadConcurrency` WUA download jobs in
  parallel (Delivery Optimization splits each job across connections). The
  install pass stays serial because CBS/TrustedInstaller takes an exclusive
  servicing lock; running installs concurrently only yields `0x80240016` /
  `1618`. A failed parallel download is not fatal — the serial install
  retries whatever is missing.
- `main`'s outer `try/catch` is only a last resort; its `finally` block pauses
  with "Press Enter to close" on both success and failure (skipped with
  `-Unattended`), so the elevated RunAs window does not vanish instantly.

| Stage | Verify check | Skip means | Error policy |
| --- | --- | --- | --- |
| `Initialize-Environment` | CurrentUser execution policy already `RemoteSigned`; directories exist | nothing to set | WARN, continue |
| `Initialize-Scoop` | `scoop` on PATH; `main` bucket present; `git` installed | scoop ready, git installed | rethrow (needed downstream) |
| `Initialize-Winget` | `winget` on PATH; sources refreshed | winget ready | missing → `Repair-Winget` (Store update scan, then GitHub msixbundle download); still missing → rethrow (needed by `install-software.ps1`) |
| `Update-Windows` | update scan returns 0 pending updates (NuGet provider and PSGallery trust prepared non-interactively); downloads use parallel WUA jobs, installs stay serial | up to date, no reboot | WARN, continue |
| `Invoke-Debloat` | stage marker `stage-debloat.done` in state dir; all four Windows Security toggles off | playbook already applied | rethrow; also blocks before the CLI when a toggle stays on |
| `Invoke-Drivers` | no present device with `Status != OK/Unknown` | all devices healthy | rethrow only on user decline; else WARN |
| `Complete-Bootstrap` | live `$PROFILE` is a symlink into this repo | link already correct | rethrow |

Stage markers are one-shot files (`<StateDir>\stage-<name>.done`); delete the
marker to force that stage to run again.

Software installation is **not** part of bootstrap. Bootstrap only initializes
the tooling (scoop with git, winget); the actual packages and installers live
in `install-software.ps1`, run separately afterwards.

## Flow

```mermaid
flowchart TD
    A([Start Bootstrap]) --> B[Load Configuration]
    B --> C[Check Administrator]
    C --> D{Elevated?}

    D -- No --> E[Relaunch as Administrator]
    E --> F[Exit Original Process]
    D -- Yes --> G[Initialize Environment]

    G --> H[Initialize Scoop - git only]
    H --> H2[Initialize Winget]
    H2 --> HW{winget on PATH?}
    HW -- No --> HR[Repair App Installer - Store update scan, then GitHub msixbundle download]
    HR --> HW2{winget available now?}
    HW2 -- No --> WERR[Log Error - rethrow]
    HW2 -- Yes --> HS
    HW -- Yes --> HS[Refresh winget sources]
    HS --> I[Update Windows - scan first, skip if current]
    I --> IU{Updates pending and confirmed?}

    IU -- No --> DJ
    IU -- Yes --> ID[Download in parallel - bounded WUA jobs]
    ID --> II[Install serially - CBS lock is exclusive]
    II --> DJ

    subgraph DEBLOAT["1. Debloat - ReviOS"]
        DJ{Stage marker exists?}
        DJ -- Yes --> DJX[Skip - already applied]
        DJ -- No --> J[Download ReviOS Playbook]
        J --> K[Verify Artifact]
        K --> L{Artifact Valid?}
        L -- No --> ERR[Log Error and Stop]
        L -- Yes --> M[Disable Defender]
        M --> MD{All 4 Windows Security toggles off?}
        MD -- Yes --> P{User confirms apply?}
        MD -- No --> MP[Prompt: turn off Tamper Protection and re-check - max 3 tries]
        MP --> MC{Still on?}
        MC -- No --> P
        MC -- Yes --> ERR
        P -- No --> DJQ[Skip by user - WARN, continue]
        P -- Yes --> O[Apply via TrustedUninstaller CLI]
        O --> Q{Apply OK?}
        Q -- No --> ERR
        Q -- Yes --> DJX
    end

    DJQ --> R

    DJX --> R{Any device unhealthy?}

    subgraph DRIVERS["2. Driver Management - MSI Laptop"]
        R -- No --> RX[Skip - devices healthy]
        R -- Yes --> S[Install MSI OEM + NVIDIA Drivers]
        S --> X[Verify Device Manager]
        X --> Y{Required Devices Working?}
        Y -- No --> ERR
        Y -- Yes --> RX
    end

    RX --> AF

    subgraph FINAL["3. Link and Verify"]
        AF --> AG{Profile already linked?}
        AG -- Yes --> AGX[Skip - link correct]
        AG -- No --> AH[Create Profile Symlink + Verify]
        AH --> AI{Link Valid?}
        AI -- No --> ERR
        AI -- Yes --> AGX
        AGX --> AJ[Save Completion State]
        AJ --> AK([Bootstrap Complete])
    end

    ERR --> AL[Save Recovery State]
    WERR --> AL
    AL --> AM([Bootstrap Failed or Needs Attention])

    AK --> PAUSE{Unattended?}
    AM --> PAUSE
    PAUSE -- No --> WAIT[Press Enter to close]
    PAUSE -- Yes --> WAITX([Exit])
    WAIT --> WAITX
```

## Files

| File | Role |
| --- | --- |
| `bootstrap.ps1` | Stage components + `main` orchestration (init, debloat, drivers, profile link) |
| `install-software.ps1` | Scoop/winget packages + external installers; run separately after bootstrap |
| `ame-cli.ps1` | `Invoke-ReviCli` — headless ReviOS apply via TrustedUninstaller CLI |
| `tests/` | Pester tests — `Bootstrap.Tests.ps1` (all bootstrap stages incl. debloat), `InstallSoftware.Tests.ps1` (software install + state file). Run with `Invoke-Pester .\tests` |
| `specs/` | Plan documents for pending/completed changes |

## Software installation

`install-software.ps1` follows the same verify-first contract as the bootstrap
stages but runs standalone, as a normal user (no elevation):

| Component | Verify check | Skip means | Error policy |
| --- | --- | --- | --- |
| `Install-ScoopPackages` | `scoop list <pkg>` lists the package | package installed | WARN per package |
| `Install-WingetPackages` | `winget list --id` finds the package | package installed | WARN per package |
| `Install-Software` | `git`/`fzf`/`zed`/`code` all on PATH | software present | rethrow |

`main` bails out early when scoop or winget is missing — run `bootstrap.ps1`
first.

Every managed package — scoop, winget and external installers — is recorded
(`installed`, `already-present` or `failed`, with tool and timestamp) to
`~\.dotfiles\software.state.json`. The file is rewritten on each run and
always holds the full inventory; a summary is printed at the end.
