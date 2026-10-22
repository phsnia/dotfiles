# Plan: Shorten the bootstrap code

Status: implemented

## Goal

`win/bootstrap.ps1` had 28 functions and 1162 lines. Every stage worked, but
the file carried a lot of scaffolding around the work: a three-function
framework for a single stage marker, a second winget repair route, a
try/catch around every single COM property, a result shape that was projected
twice and a four-tag doc block on every function.

Decisions:

- **A helper may stay only when it supports the core (a shared utility) or is
  a structural part of a core** (the core split into its natural steps).
  Everything else folds into its caller.
- **One descriptive line per function.** The `@param/@return/@example` blocks
  are gone; the "why" notes stay as plain comments next to the code.
- **No feature loss.** Every stage stays: elevation, environment, scoop,
  winget, Windows Update, Defender, debloat, drivers, profile link and the
  state file.
- **The winget repair has one route**: the latest winget-cli release from
  GitHub. The Microsoft Store update-scan route is gone.

## Changes

### `win/bootstrap.ps1`

1. **The file is split into core and support.** Section 2 holds the helpers
   the stages share; every other section is a stage (the core) with the steps
   it is built from.

   | Core | Its structural parts |
   | --- | --- |
   | Windows Update | `Search-WindowsUpdates` → `Get-UpdateSummary` → `Install-WindowsUpdates` → `Test-RebootRequired` |
   | Winget | `Test-WingetAvailable` → `Install-WingetFromRelease` |
   | Defender | `Get-DefenderTogglesOn` → `Invoke-DefenderCheck` |
   | Drivers | `Get-UnhealthyDevices` → `Invoke-Drivers` |
   | Profile | `Test-ProfileLinked` → `Complete-Bootstrap` |

   The shared helpers that stay: `Confirm-Step`, `Write-StateFile`,
   `Update-SessionPath` and `Release-Com`. The download wrapper
   (`Get-RemoteFile`) and the artifact check (`Test-Artifact`) stay in
   `lib/common.ps1`.

2. **Five functions folded into their caller:**

   | Helper | Folded into | Why |
   | --- | --- | --- |
   | `Get-StageMarkerPath`, `Test-Stage`, `Complete-Stage` | `Invoke-Debloat` | a three-function framework around one marker file of one stage |
   | `Resolve-ProfilePath` | `Complete-Bootstrap` | a one-line path choice with one caller |
   | `Install-WingetFromStore` | — | the second route of one goal |

3. **The winget repair has one route.** A missing winget is repaired from the
   latest winget-cli release (`.msixbundle` plus the x64 dependency
   packages). The Store update-scan route is gone: it needed an MDM CIM
   provider that most machines do not have and only ever delayed the GitHub
   download.

4. **The logic is compressed:**
   - the per-field try/catch around `ResultCode`, `HResult`,
     `RebootRequired`, `KBArticleIDs` and `MaxDownloadSize` is gone; one
     guarded read per update is enough,
   - one result shape flows through the update stage (object → hashtable →
     print shape is now object → print shape),
   - the debloat stage no longer downloads and verifies the playbook itself:
     `Invoke-ReviCli` does both,
   - `Initialize-Environment` creates the missing directories with one
     `New-Item` call and one message instead of one per directory.

5. **The state file keeps only what is read.** The `windowsUpdate` block
   holds `checkedAt`, `skipped`, `upToDate`, `pendingCount`, `pendingSizeMb`,
   `rounds`, `installed`, `failed` and `rebootRequired`. The per-update
   `results` array is gone — nothing read it.

Result: 23 functions (9 stages + 14 support/structural) in ~905 lines, with
the doc-comment overhead down from 244 to 180 lines.

### `win/tests/Bootstrap.Tests.ps1`

6. The `Stage markers` context is gone: the marker is part of the debloat
   stage now, and the debloat context already proves that the marker is
   written, skipped and left alone when the stage is declined.
7. The loading assertions require the folded functions to be gone
   (`Get-StageMarkerPath`, `Test-Stage`, `Complete-Stage`,
   `Resolve-ProfilePath`, `Install-WingetFromStore`).
8. The `Initialize-Winget` context mocks the one repair route instead of two.
9. The `Initialize-Environment` test expects one `New-Item` call that covers
   every missing directory.
10. The debloat happy path expects two downloads (the CLI archive and the
    playbook, both from the CLI) instead of three.
11. The state file test asserts that the `results` key is gone.

### `win/ARCHITECTURE.md`

12. The winget repair is documented as the GitHub route only.
13. The flow diagram drops the Store repair node and the playbook download
    and verify nodes.
14. The state file section lists the keys that are actually written.

### `win/README.md`

15. The layout tree lists the new plan document.

## Verification

1. Parse every `win/**/*.ps1` with
   `[System.Management.Automation.Language.Parser]::ParseFile` — zero parse
   errors.
2. Run `Invoke-Pester .\win\tests` — 65 tests, all pass.
3. Live check on the machine: `Invoke-DefenderCheck -Unattended` reports
   "Windows Defender is off; nothing to do." (all four toggles are off) and
   returns `$true`.

## Notes

- The stage functions are the ones `main` calls; the support helpers are the
  ones the stages share. Nothing else earned its place.
- `lib/common.ps1`, `ame-cli.ps1` and `install-software.ps1` are untouched:
  they still use the `@param/@return/@example` doc blocks.
- The historical plan documents under `win/specs/` are records of past
  decisions and keep the old function names.
