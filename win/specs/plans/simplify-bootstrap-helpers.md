# Plan: Simplify the bootstrap helpers

Status: implemented

## Goal

`win/bootstrap.ps1` had grown to 48 functions and ~1430 lines. Most of them
were one-off wrappers: a function called from exactly one place, holding a
handful of lines that the caller could just as well do itself. The file has
one job — run the stages — so the helpers are only worth their keep when they
support a stage.

Decisions:

- **A helper stays when it is a stage, is called from two or more places, or
  holds logic that would otherwise dominate its caller** (COM setup/teardown,
  defensive reads from COM). Everything else is merged into the caller.
- **No behaviour change.** The only differences are the three noted below.
- **The doc block stays**, but the content shrinks to one description line
  plus the "why" notes.

## Changes

### `win/bootstrap.ps1`

1. **Dead code deleted** — `Test-DefenderOff` had no call site.
2. **19 helpers merged into their caller:**

   | Helper | Merged into |
   | --- | --- |
   | `Start-Bootstrap`, `Save-RecoveryState` | `main` |
   | `Save-CompletionState`, `Link-Profile` | `Complete-Bootstrap` |
   | `Set-ExecutionPolicyRemoteSigned`, `Ensure-Directory` | `Initialize-Environment` |
   | `Install-Scoop`, `Add-ScoopBucket`, `Install-ScoopPackage` | `Initialize-Scoop` |
   | `Repair-Winget` | `Initialize-Winget` |
   | `Get-AppInstallerDependencies` | `Install-WingetFromRelease` |
   | `Show-PendingUpdates`, `Format-UpdateSize`, `Get-UpdateSizeTotal`, `Release-Search` | `Invoke-WindowsUpdates` |
   | `Get-UpdateSizeMb` | `Get-UpdateSummary` |
   | `Show-DefenderSettings` | `Invoke-DefenderCheck` |
   | `Install-MsiDrivers`, `Install-NvidiaDriver` | `Invoke-Drivers` |

3. **The update summary carries the size in MB.** `Get-UpdateSizeMb` and
   friends were written for PSWindowsUpdate, which reports the size as
   `'44MB'`, a raw byte count or an array of both. The stage uses the built-in
   Windows Update client API, where the size is always a byte count, so the
   unit parsing could never run. `Get-UpdateSummary` now returns `SizeMb`
   (a double, `$null` when the client does not know the size) and the stage
   prints and sums it.
4. **The dead summary fields are gone** — `Mandatory` and `Downloaded` were
   read defensively and never consumed.
5. **`$script:ProfilePathExplicit` is gone.** The flag only differed from
   `if ($ProfilePath)` when an empty string was passed, which behaved the
   same way.
6. **Tamper Protection fails closed.** A toggle that cannot be read counts as
   on: unknown must not open the gate to a protected machine. Without the
   Defender module there is nothing to report at all.
7. **The size guard is gone.** `MaxDownloadSize` is a 32-bit ULONG; masking it
   back to 32 bits always leaves a plausible value, so the "implausible size"
   branch could never run.

Result: 28 functions (9 stages + 19 support helpers) in ~1160 lines.

### `win/tests/Bootstrap.Tests.ps1`

8. The loading assertions drop the merged helpers and require the removed
   ones to be gone.
9. The `Repair-Winget` context is gone; the `Initialize-Winget` context mocks
   the two repair routes (`Install-WingetFromStore`, `Install-WingetFromRelease`)
   instead.
10. The `Format-UpdateSize` and `Get-UpdateSizeTotal` contexts become a
    `Get-UpdateSummary` context (size in MB, no size, masked upper bits).
11. The update fixtures carry `SizeMb` instead of the raw bytes.
12. The state file test calls `Complete-Bootstrap` (the completion state lives
    there now) instead of the removed `Save-CompletionState`.
13. The `main` context drops the `Start-Bootstrap` mock; the expected order
    starts at `Assert-Administrator`.

### `win/tests/Defender.Tests.ps1`

14. Only the two remaining Defender functions are loaded.
15. The `Show-DefenderSettings` mock becomes a `Start-Process` mock that
    counts the opened pages; the page fallback is tested through
    `Invoke-DefenderCheck`.
16. A new test proves the fail-closed Tamper read: a toggle that cannot be
    read is reported as on.

### `win/ARCHITECTURE.md`

17. The `Repair-Winget` and `Show-PendingUpdates` mentions are replaced by the
    new wording; the Defender section documents the fail-closed read.

## Verification

1. Parse every `win/**/*.ps1` with
   `[System.Management.Automation.Language.Parser]::ParseFile` — zero parse
   errors.
2. Run `Invoke-Pester .\win\tests` — 66 tests, all pass.
3. Live check on the machine: `Invoke-DefenderCheck -Unattended` reports
   "Windows Defender is off; nothing to do." (all four toggles are off) and
   returns `$true`.

## Notes

- The stage functions are the ones `main` calls; the support helpers are the
  ones the stages share. Nothing else earned its place.
- `lib/common.ps1`, `ame-cli.ps1` and `install-software.ps1` are untouched:
  they share their helpers with each other, not with the bootstrap stages.
- The historical plan documents under `win/specs/` are records of past
  decisions and keep the old function names.
