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
- **Error handling inside** — each component wraps its work in `try/catch`
  itself. Best-effort components (updates, scoop packages, winget packages,
  drivers) log a `WARN` and let the bootstrap continue; critical components
  (debloat apply, profile link) log `ERROR` and rethrow so `main` can save
  the recovery state and stop.
- `main`'s outer `try/catch` is only a last resort.

| Stage | Verify check | Skip means | Error policy |
| --- | --- | --- | --- |
| `Initialize-Environment` | CurrentUser execution policy already `RemoteSigned`; directories exist | nothing to set | WARN, continue |
| `Initialize-Scoop` | `scoop` on PATH; `main` bucket present | scoop ready | rethrow (needed downstream) |
| `Update-Windows` | update scan returns 0 pending updates | up to date, no reboot | WARN, continue |
| `Invoke-Debloat` | stage marker `stage-debloat.done` in state dir | playbook already applied | rethrow |
| `Invoke-Drivers` | no present device with `Status != OK/Unknown` | all devices healthy | rethrow only on user decline; else WARN |
| `Install-ScoopPackages` | `apps\<pkg>\current` exists (user or ProgramData scoop) | package installed | WARN per package |
| `Install-WingetPackages` | `winget list --id` finds the package | package installed | WARN per package |
| `Install-Software` | `git`/`fzf`/`zed`/`code` all on PATH | software present | rethrow |
| `Complete-Bootstrap` | profile is a symlink into this repo | link already correct | rethrow |

Stage markers are one-shot files (`<StateDir>\stage-<name>.done`); delete the
marker to force that stage to run again.

## Flow

```mermaid
flowchart TD
    A([Start Bootstrap]) --> B[Load Configuration]
    B --> C[Check Administrator]
    C --> D{Elevated?}

    D -- No --> E[Relaunch as Administrator]
    E --> F[Exit Original Process]
    D -- Yes --> G[Initialize Environment]

    G --> H[Initialize Scoop]
    H --> I[Update Windows - scan first, skip if current]

    subgraph DEBLOAT["1. Debloat - ReviOS"]
        I --> DJ{Stage marker exists?}
        DJ -- Yes --> DJX[Skip - already applied]
        DJ -- No --> J[Download ReviOS Playbook]
        J --> K[Verify Artifact]
        K --> L{Artifact Valid?}
        L -- No --> ERR[Log Error and Stop]
        L -- Yes --> M[Disable Defender]
        M --> O[Apply via TrustedUninstaller CLI]
        O --> Q{Apply OK?}
        Q -- No --> ERR
        Q -- Yes --> DJX
    end

    DJX --> R{Any device unhealthy?}

    subgraph DRIVERS["2. Driver Management - MSI Laptop"]
        R -- No --> RX[Skip - devices healthy]
        R -- Yes --> S[Install MSI OEM + NVIDIA Drivers]
        S --> X[Verify Device Manager]
        X --> Y{Required Devices Working?}
        Y -- No --> ERR
        Y -- Yes --> RX
    end

    RX --> SW{git/fzf/zed/code on PATH?}

    subgraph SOFTWARE["3. Software Installation"]
        SW -- Yes --> SWX[Skip - already installed]
        SW -- No --> AA[Install Scoop + winget Packages]
        AA --> AB[Download + Run External Installers]
    end

    SWX --> AF[Verify Software Installation]

    subgraph FINAL["4. Link and Verify"]
        AF --> AG{Profile already linked?}
        AG -- Yes --> AGX[Skip - link correct]
        AG -- No --> AH[Create Profile Symlink + Verify]
        AH --> AI{Link Valid?}
        AI -- No --> ERR
        AI -- Yes --> AGX
        AGX --> AJ[Save Completion State]
        AJ --> AK([Bootstrap Complete])
    end

    ERR --> AL[Save Logs and Recovery State]
    AL --> AM([Bootstrap Failed or Needs Attention])
```

## Files

| File | Role |
| --- | --- |
| `bootstrap.ps1` | Stage components + `main` orchestration |
| `ame-cli.ps1` | `Invoke-ReviCli` — headless ReviOS apply via TrustedUninstaller CLI |
| `Debloat.Tests.ps1` | Pester tests for the debloat flow |
| `DEBLOAT.md` | Debloat stage details (CLI, option ids, techniques) |
