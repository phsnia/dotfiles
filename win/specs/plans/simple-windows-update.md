# Plan: Simple Windows Update stage

Status: superseded by `verify-windows-update.md` (the stage verifies and
reports only — installing was removed, and the scan moved to the built-in
Windows Update client API, so the PSWindowsUpdate pre-flight went away too).

## Goal

Make the Windows Update stage small enough to read in one pass: one scan,
one report, one confirmation, one install. The bespoke parallel download
machinery goes away.

Decisions:

- **No pre-download phase.** `Get-WindowsUpdate -Install` downloads and
  installs in the same pass; the Windows Update service already fetches
  content over several connections on its own (Delivery Optimization).
- **No concurrency knob.** `$Config.UpdateDownloadConcurrency` and the
  runspace pool, the WUA COM interop and the second scan are removed.
- **Installs stay serial** — CBS/TrustedInstaller holds an exclusive
  servicing lock, so concurrent installs only produce `0x80240016` / `1618`.
  One install pass is serial by definition.
- **Size formatting moves out** into `Format-UpdateSize`, so the stage
  body only reads "report the pending updates".

## Changes

### `win/bootstrap.ps1`

1. Delete `Invoke-ParallelUpdateDownload` (runspace pool, WUA
   `IUpdateDownloader` COM interop, progress polling) and the
   `$Config.UpdateDownloadConcurrency` entry.
2. New `Format-UpdateSize` — normalizes the shapes PSWindowsUpdate reports
   (`'44MB'`, a raw byte count, an array of both) into an MB string; the
   raw value is returned when the format is unknown, an empty string when
   the size is missing.
3. `Update-Windows` keeps the NuGet provider / PSGallery / module
   pre-flight, then: scan once → print the pending updates → confirm →
   `Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot`. The parallel
   download branch and its `try/catch` are gone.

### `win/tests/Bootstrap.Tests.ps1`

4. Drop the `Invoke-ParallelUpdateDownload` mock, its loading assertion
   and `UpdateDownloadConcurrency` from the test config.
5. Replace the three parallel-download tests with: "scans once and installs
   once" (`Get-WindowsUpdate` called twice — one scan, one install) and
   "installs in a single pass after the scan" (call order `scan>install`).
6. New `Format-UpdateSize` context: unit-suffixed size, raw byte count,
   size array, missing size.

### `win/ARCHITECTURE.md`, `win/README.md`

7. Contract bullet → "One scan, one install"; `Update-Windows` row drops
   the parallel-download wording; flow diagram loses the parallel download
   node; new "Windows Update" section describes the five steps.
8. README layout lists the real `specs/` tree and the new plan.

### `win/specs/plans/parallel-update-download.md`

9. Marked as superseded by this plan.

## Verification

1. Parse `bootstrap.ps1` and `Bootstrap.Tests.ps1` with
   `[System.Management.Automation.Language.Parser]::ParseFile` — zero parse
   errors.
2. Grep `win/` for `Invoke-ParallelUpdateDownload` and
   `UpdateDownloadConcurrency` — zero matches remain.
3. Run `Invoke-Pester win\tests\Bootstrap.Tests.ps1` — 39 tests pass.
