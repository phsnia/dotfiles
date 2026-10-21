# Plan: Parallel Windows Update downloads

Status: superseded by `simple-windows-update.md` (the parallel pre-download
was removed again — the Windows Update service downloads on its own, so the
extra WUA interop bought nothing).

## Goal

Download pending Windows updates concurrently. Installing stays serial — CBS
and TrustedInstaller hold an exclusive servicing lock, so parallel installs
would only produce `0x80240016` (`WU_E_INSTALL_NOT_ALLOWED`) or MSI `1618`.

## Feasibility (checked before implementing)

- **Downloads:** independent of each other. WUA accepts several download jobs,
  and Delivery Optimization opens multiple concurrent connections. The WUA
  `IUpdateDownloader` is per-job; one job per update is enough.
- **Installs:** serialized by the WU service and CBS. Not changed.
- **Elevation:** WUA scans work unelevated, downloads do not (`0x80240044`,
  `WU_E_NOT_ADMIN`). Bootstrap already runs elevated.
- **Async API:** `BeginDownload` is unusable from PowerShell — passing null
  callbacks throws `NullReferenceException`, and implementing the callback
  interfaces requires compiled interop. Synchronous `Download()` in runspaces
  is the practical route.
- **Update objects:** `IUpdate` COM objects from one scan can be handed to
  other runspaces and added to a collection built from a fresh
  `Microsoft.Update.Session`; verified by dispatching a download and receiving
  `0x80240044` rather than a marshaling error. This avoids one extra WU scan
  per worker (several seconds each).
- **PSWindowsUpdate:** `Get-WindowsUpdate -Download` uses one
  `IUpdateDownloader.Download()` over the whole collection; it exposes no
  concurrency knob, which is why the pre-download is bespoke.

## Changes

### `win/bootstrap.ps1`

1. `$Config.UpdateDownloadConcurrency = 4` — worker count; 1 disables the
   parallel pre-download.
2. New `Invoke-ParallelUpdateDownload`:
   - one unelevated-safe WUA scan (`IsInstalled=0 and IsHidden=0 and
     Type='Software'`);
   - round-robin slices of the `IUpdate` objects;
   - runspace pool (max `Concurrency`) where each worker opens its own
     `Microsoft.Update.Session`, skips `IsDownloaded` updates, and calls
     `Download()` on a one-update collection;
   - returns `UpdateID`, `Title`, `Ok`, `Message` per update; per-worker and
     per-update failures are captured, never thrown.
3. `Update-Windows` calls it after the confirmation gate and before
   `Get-WindowsUpdate -Install` (skipped for a single update). The call is
   wrapped in `try/catch`: a failed pre-download falls back to the install
   pass, which downloads whatever is still missing. Installs remain serial.

### `win/tests/Bootstrap.Tests.ps1`

4. Config gains `UpdateDownloadConcurrency = 4`; the loading test asserts the
   new function; the `Update-Windows` context mocks the pre-download.
5. New tests: parallel download runs before install, single update skips it,
   a throwing download still installs.

### `win/ARCHITECTURE.md`, `win/README.md`

6. Update-stage row, contract bullet (downloads overlap, installs do not),
   flow diagram, and the specs listing.

## Verification

1. Parse `bootstrap.ps1` with `[Parser]::ParseFile` — zero errors.
2. Run `Invoke-ParallelUpdateDownload -Concurrency 4` unelevated: two pending
   updates returned `Ok = True` (`already downloaded`) from a single scan
   (wall time varies with the WU service).
3. Force the download branch (temporarily bypass `IsDownloaded`): two workers
   returned `Ok = False` with `0x80240044` — proves concurrent dispatch and
   error aggregation; actual transfer needs elevation.
4. `Invoke-Pester win\tests\Bootstrap.Tests.ps1` — 36 tests pass.

## Notes

- Round-robin slices balance package count, not bytes; a large cumulative
  update can still dominate.
- `Update-Windows` still runs a PSWindowsUpdate scan for the report, so the
  stage scans twice. Merging them would mean replacing the PSWindowsUpdate
  output/size handling and its tests — out of scope here.
