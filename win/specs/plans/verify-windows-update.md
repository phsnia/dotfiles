# Plan: Windows Update check without install

Status: superseded by `merge-update-into-bootstrap.md` (the stage installs
now — it scans, installs the pending updates and scans again until no update
package is left; the scan itself stayed on the built-in Windows Update
client API, so the PSWindowsUpdate pre-flight still goes away).

## Goal

The Windows Update stage verifies whether Windows is up to date and reports
the result. It never installs — not with `-AcceptAll`, not unattended. The
bootstrap becomes a "prepare and verify" run: everything it touches is
reversible setup, and the one irreversible step (installing updates, which
means a reboot later) stays with the user.

The file also gets a shape that reads top-down instead of growing a new
helper wherever the last stage needed one.

Decisions:

- **Scan with the built-in Windows Update client API**
  (`Microsoft.Update.Session`, criteria `IsInstalled=0 and IsHidden=0`)
  instead of `PSWindowsUpdate`. The scan needs no elevation, no module, no
  NuGet provider and no PSGallery trust, so the whole pre-flight
  (`Install-PackageProvider`, `Set-PSRepository`, `Install-Module`) goes
  away. It also runs in a console where PSWindowsUpdate refuses to work.
- **No approval either.** `Approve` in WUA is what lets the client install
  the update on its own later, so the scan approves nothing.
- **`-AcceptAll` is not an option** — there is nothing left to accept. The
  only new switch is `-SkipUpdateCheck`.
- **Interactive runs hand over** by opening `ms-settings:windowsupdate`;
  `-Unattended` opens nothing and still installs nothing.
- **Keep one file.** The restructure happens inside `bootstrap.ps1`; only
  genuinely shared helpers move, to `lib/common.ps1`.

## Changes

### `win/lib/common.ps1` (new)

1. `Get-RemoteFile` and `Test-Artifact` move here from
   `install-software.ps1`; both files that need them dot-source this one.

### `win/bootstrap.ps1`

2. Reorganized into eleven numbered sections (Configuration, Helpers,
   Environment, Scoop, Winget, Windows Update, Windows Defender, Debloat,
   Drivers, Profile, Entry point) with a header that maps them.
3. `Update-Windows` → `Test-WindowsUpdates`. New `Get-PendingWindowsUpdates`
   (COM scan, releases every COM object through `Release-Com`), plus
   `Get-UpdateSizeMb` (extracted from `Format-UpdateSize` so sizes can be
   summed, not just printed), `Get-UpdateSizeTotal` and
   `Show-PendingUpdates`. `MaxDownloadSize` is a 32-bit ULONG that the COM
   binder returns with junk in the upper bits — masked to 32 bits and
   dropped when implausible.
4. Deleted: `Initialize-WindowsUpdate` (NuGet/PSGallery/module pre-flight)
   and `Set-PSGalleryTrusted`.
5. `-SkipUpdateCheck` parameter, forwarded by `Assert-Administrator` in the
   RunAs relaunch so the second run keeps it.
6. The result is saved as the `windowsUpdate` block (`checkedAt`,
   `skipped`, `upToDate`, `pendingCount`, `pendingSizeMb`) by
   `Save-CompletionState`.
7. `Confirm-DefenderStep` deleted — it was identical to `Confirm-Step`, so
   the Defender prompt helper merged into it (the prompt itself now lives in
   `Disable-Defender`).
8. `$Config.UpdateSettings` (`ms-settings:windowsupdate`).

### `win/install-software.ps1`, `win/ame-cli.ps1`

9. Both drop their local copies of `Get-RemoteFile` / `Test-Artifact` and
   dot-source `lib/common.ps1` (the `ame-cli.ps1` fallback also gains
   `Test-Artifact`, which it used but never defined).

### `win/tests/`

10. `Bootstrap.Tests.ps1` — dot-source `lib/common.ps1`; new "Windows
    update check" context (up to date, report without installing, never
    installs, never asks, opens the page, opens nothing unattended, skips,
    records state) and a `Get-UpdateSizeTotal` context; loading assertions
    follow the new function names; `UpdateSettings` added to the test
    config; `main` order string expects `Test-WindowsUpdates`.
11. `Defender.Tests.ps1` — `Confirm-Step` instead of
    `Confirm-DefenderStep`, plus a `Set-MpPreference` stub: Pester builds
    its mock proxy from the real cmdlet's parameters, and this host's
    Defender module has no `-DisableTamperProtection`.
12. `InstallSoftware.Tests.ps1` — dot-source `lib/common.ps1`.

### Docs

13. `win/ARCHITECTURE.md` — contract bullet "One check, no install";
    `Test-WindowsUpdates` stage row; flow diagram branch now reports and
    opens Settings; rewritten "Windows Update" section; `lib/common.ps1`
    in the Files table.
14. `win/README.md` — bootstrap paragraph describes the check, layout tree
    gains `lib/`.
15. `simple-windows-update.md` marked superseded by this plan.

## Verification

1. Parse `bootstrap.ps1`, `install-software.ps1`, `ame-cli.ps1`,
   `lib/common.ps1` and the three test files with
   `[System.Management.Automation.Language.Parser]::ParseFile` — zero parse
   errors.
2. Grep the `.ps1` files for `Update-Windows`, `PSWindowsUpdate`,
   `Set-PSGalleryTrusted`, `Initialize-WindowsUpdate`,
   `Confirm-DefenderStep` — zero matches remain.
3. Run `Invoke-Pester .\tests` — 69 tests pass.
4. Live smoke test: the COM scan reports the pending update (KB5071959,
   1,572.9 MB), installs nothing, opens nothing under `-Unattended`, and
   writes the `windowsUpdate` block to `bootstrap.state.json`.
