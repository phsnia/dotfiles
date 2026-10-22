# Plan: Merge the Windows Update installer into bootstrap

Status: implemented

## Goal

`win/update.ps1` is a standalone Windows Update installer (PSWindowsUpdate,
transcript logging, scan → confirm → install). It duplicates the elevation,
reporting and state handling that `bootstrap.ps1` already does for every other
stage, and it is not part of the documented flow — the README layout does not
even list the file.

Merge it into `bootstrap.ps1`, into the stage that already exists
(`Test-WindowsUpdates`, today scan-and-report only), and give that stage the
loop the standalone script lacked:

> Every round starts with a **full scan** that prints the complete pending
> inventory, the install runs on exactly that set, and the stage repeats
> scan → install **until a scan comes back with no pending update packages
> left**. Only then is the stage done.

One install pass rarely finishes the job: a cumulative update supersedes the
one that was pending, a dependency chain only surfaces after its parent lands.
The loop is the point — the stage ends on an empty scan, not on "one pass
done".

Decisions:

- **One file.** `update.ps1` is deleted. Its useful parts (elevation, the
  pending-update report, the confirmation gate, the summary) move into
  `bootstrap.ps1`, which already elevates itself through
  `Assert-Administrator`. Nothing in the repo references `update.ps1`.
- **No log file.** The transcript of `update.ps1` is not ported: the console
  keeps the plain `==>` output the repo uses everywhere, and the result of
  the stage lands in `bootstrap.state.json` (see `simple-echo-logging.md`).
- **COM, not PSWindowsUpdate.** The install uses the same
  `Microsoft.Update.Session` API the scan already uses
  (`CreateUpdateDownloader().Download()` → `CreateUpdateInstaller().Install()`).
  No NuGet provider, no PSGallery repository, no `Install-Module`, no module
  trust prompt — the bootstrap never installs a PowerShell module from the
  internet. This keeps the decision recorded in `verify-windows-update.md`;
  the merge changes *what* the stage does, not *how* it reaches Windows Update.
- **Scan → install → scan, until empty.** One scan per round, used for both
  the report and the install (a second scan costs seconds and hits the
  network).
- **Round cap.** `$Config.UpdateMaxRounds = 5`, plus a no-progress guard: a
  round that installs nothing ends the loop with a warning. A machine that
  keeps offering packages cannot spin forever.
- **A pending reboot ends the round, not the run.** With a reboot pending, the
  next scan returns the same packages forever, so the stage stops, records
  `rebootRequired` and lets the bootstrap continue. The next bootstrap run
  picks the rest up — the stage is verify-first, so it converges over runs.
  **The script never reboots by itself.**
- **Confirmation before every install.** The pending list is printed first,
  then `Confirm-Step` asks once per round (auto-yes under `-Unattended`, the
  same auto-confirm `Confirm-Step` already does). The standalone script asked
  once per run; per round matches the loop.
- **No auto-restart.** The reboot is left to the user (the standalone script
  did the same through `-IgnoreReboot`).
- **`-SkipUpdateCheck` stays.** It now skips the whole stage — scan *and*
  install. The name is kept so the documented command line keeps working.
- **The stage runs first.** It moved in front of the environment, scoop and
  winget stages: the machine is patched before anything else touches it. It
  still runs after `Assert-Administrator` — the download needs the elevation.
- **Best-effort, like today.** A failed install logs a warning and the
  bootstrap continues; the update stage is not critical for the profile link.

## The merged stage

```
Invoke-WindowsUpdates
  rounds = 0, installed = 0, failed = 0, upToDate = false, reboot = false

  for round in 1..$Config.UpdateMaxRounds
      search = Search-WindowsUpdates            # one full scan
      summaries = summaries of every update in the search

      if summaries is empty -> upToDate = true; break        # no packages left
      Show-PendingUpdates summaries            # the complete inventory
      if user declines -> break

      results = Install-WindowsUpdates -Search search         # download + install
      report per update: KB, ResultCode, HRESULT

      if nothing was installed -> warn "no progress"; break
      if Test-RebootRequired -> reboot = true; break

  record the state block
```

The loop therefore stops for exactly three reasons: **no packages left**
(done), **a reboot is pending** (resume after the reboot), or **no progress /
round cap** (warn and move on).

## Changes

### `win/bootstrap.ps1`

1. Section 6 header: "Windows Update (verify only)" → "Windows Update (scan,
   install, repeat)"; the file header map (item 6) follows.
2. `Test-WindowsUpdates` → `Invoke-WindowsUpdates`: the loop above. It writes
   `$script:UpdateCheckResult` and nothing else; the stage stays best-effort
   (WARN, continue).
3. `main` runs the stage first: `Start-Bootstrap` → `Assert-Administrator` →
   `Invoke-WindowsUpdates` → `Initialize-Environment` → `Initialize-Scoop` →
   `Initialize-Winget` → `Invoke-Debloat` → `Invoke-Drivers` →
   `Complete-Bootstrap`. The file header notes that the stages do not run
   in the order of the sections.
4. New `Search-WindowsUpdates`: the COM scan
   (`Microsoft.Update.Session` → `CreateUpdateSearcher()` →
   `Search('IsInstalled=0 and IsHidden=0')`), returning the live objects
   (session, searcher, result, update collection) so one scan can feed both
   the report and the install. `ServerSelection = 2` and
   `ServiceID = '7971F918-A847-4430-9279-4A52D1EFE18D'` target Microsoft
   Update, so a WSUS-managed machine is not silently held back.
5. New `Get-UpdateSummary -Update <IUpdate>`: one update → the summary
   object the report and the size helpers already consume
   (`Title`, `Size`, `KB`, `Mandatory`, `Downloaded`). `MaxDownloadSize` stays
   masked to 32 bits and dropped when implausible.
6. `Get-PendingWindowsUpdates` is deleted — its body becomes
   `Search-WindowsUpdates` + `Get-UpdateSummary`. The scan now has to keep its
   COM objects alive for the install, which a "return summaries and release"
   function cannot do.
7. New `Install-WindowsUpdates -Search <search>`: download then install, and
   report per update (`Title`, `KB`, `ResultCode`, `HResult`,
   `RebootRequired`). `AcceptEula()` on updates whose `EulaAccepted` is 0.
   Installs stay serial — CBS/TrustedInstaller holds an exclusive servicing
   lock (`0x80240016` otherwise). Every COM object is released through
   `Release-Com`.
8. New `Test-RebootRequired -Result <installerResult>`: the installer's
   `RebootRequired` flag plus the three registry signals — CBS
   `RebootPending`, `WindowsUpdate\Auto Update\RebootRequired` and
   `PendingFileRenameOperations`.
9. No log file and no system snapshot: the stage prints through the plain
   `==>` output and records its result in the state file.
10. `$Config`: `UpdateMaxRounds = 5` is added; `UpdateSettings` stays (it is
    still the hand-over target when the user declines).
11. The state block `windowsUpdate` keeps `checkedAt`, `skipped`,
    `upToDate`, `pendingCount`, `pendingSizeMb` and gains `rounds`,
    `installed`, `failed`, `rebootRequired` and `results` (per update:
    `kb`, `title`, `resultCode`, `hResult`).

### `win/update.ps1` (deleted)

12. The file is deleted: its own elevation block (bootstrap elevates), the
    NuGet/PSGallery/PSWindowsUpdate pre-flight (COM instead), the transcript
    (the console output + the state block), and the standalone main flow.

### `win/tests/Bootstrap.Tests.ps1`

13. The "Windows update check" context becomes "Windows update stage" (13
    tests):
    - "reports up to date when the scan is empty" — no install, `upToDate`.
    - "installs exactly the scanned set" — two packages, the installer is
      called once with the same collection, the user is asked once.
    - "scans again until no packages remain" — the search returns a package
      on the first call and an empty collection on the second: one install,
      two rounds, `upToDate` at the end.
    - "stops when a reboot is required" — one round, `rebootRequired` true,
      no second search and no second install.
    - "stops after the round cap" — the search always returns a package:
      the rounds stop at `UpdateMaxRounds`.
    - "stops when a round installs nothing" — the installer installs
      nothing: one round, a warning, no re-scan.
    - "does not install when the user declines" — no install call, no throw.
    - "opens the Windows Update page when the install is declined".
    - "never reboots the machine" — `Restart-Computer` is never called.
    - "continues when the scan fails" — a throwing scan does not break the
      bootstrap.
    - "skips the stage when -SkipUpdateCheck is passed" — no search,
      `skipped` true.
    - "never touches PSWindowsUpdate, a package provider or a repository" —
      the COM route is the guarantee that the stage needs no module.
    - "records the result in the state file" — `upToDate`, `rounds`,
      `installed`, `rebootRequired`.
14. The old "never installs an update" test is replaced by the inverted one
    above (the stage installs now).
15. The loading assertions follow the new names (`Invoke-WindowsUpdates`,
    `Search-WindowsUpdates`, `Get-UpdateSummary`, `Install-WindowsUpdates`,
    `Test-RebootRequired`, `Release-Search` exist; `Test-WindowsUpdates` and
    `Get-PendingWindowsUpdates` are gone).
16. The `main` order string becomes
    `… > Assert-Administrator > Invoke-WindowsUpdates > Initialize-Environment > …`.

### `win/ARCHITECTURE.md`

17. Contract bullet "One check, no install" → "Scan, install, repeat until
    clean"; the `Test-WindowsUpdates` stage row becomes
    `Invoke-WindowsUpdates` (verify: an empty scan; error policy: WARN,
    continue) and moves to the top of the stage table (the table follows the
    run order).
18. The flow diagram's update branch becomes scan → pending? → report →
    confirm → install → reboot? → scan again, and moves in front of the
    environment/scoop/winget branch (right after the elevation).
19. The "Windows Update" section is rewritten: the loop, the round cap, the
    no-progress guard, the reboot rule, the state block. The "no install
    phase, no download phase" paragraph goes away — there is a download phase
    now (it is the downloader's own, one call per round).

### `win/README.md`

20. The bootstrap paragraph: the stage scans, installs and repeats until no
    update packages remain; `-SkipUpdateCheck` skips the stage. The layout
    tree gains this plan and marks `verify-windows-update.md` as superseded.

### `win/specs/plans/verify-windows-update.md`

21. Marked superseded by this plan — its "never installs" decision is
    reversed; the scan part (COM, no module, no approval) is kept.

## Verification

1. Parse `bootstrap.ps1` and `Bootstrap.Tests.ps1` with
   `[System.Management.Automation.Language.Parser]::ParseFile` — zero parse
   errors.
2. Grep `win/` for `Test-WindowsUpdates`, `Get-PendingWindowsUpdates`,
   `PSWindowsUpdate`, `Install-Module`, `update.ps1` — only the negative
   test assertions remain.
3. Run `Invoke-Pester .\win\tests` — 68 tests pass (63 before; the update
   context grew from 8 to 13 tests).
4. Live smoke test on a machine with pending updates: the scan prints the
   inventory, the install runs, the next scan comes back empty and the state
   file holds `upToDate: true`, `installed > 0`, `rounds >= 2`.

## Notes

- A cumulative update takes 10–40 minutes and wants a reboot; a bootstrap run
  with the stage enabled gets long. `-SkipUpdateCheck` skips it.
- Windows Update can be held back by a metered connection, a WSUS policy or a
  third-party driver — the install result then carries an HRESULT
  (`0x80070422` service disabled, `0x80240016` another install in progress,
  `0x80070070` disk full). The stage reports it per update and continues.
- Without the reboot guard the loop would spin until the round cap on a
  machine that is waiting for a reboot — the guard is what makes "scan until
  no packages remain" terminate.
- The stage runs first (right after the elevation): the machine is patched
  before scoop, winget, the debloat and the drivers touch it. The elevation
  stays in front of it — the download needs it — and a pending reboot never
  blocks the remaining stages.
- `-Unattended` now installs without asking. That is the point of the
  unattended run; `-SkipUpdateCheck` is the way to keep an unattended run from
  touching Windows Update.
