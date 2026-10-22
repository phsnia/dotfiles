# Plan: Fix the Defender toggle detection

Status: implemented

## Goal

The Defender stage reported toggles that were already off, so the user could
not get past it:

```
==> Still on: Cloud-delivered protection, Automatic sample submission
==> Turn them off in Windows Security > Virus & threat protection > Manage settings (Tamper protection first).
```

Real-time protection and Tamper Protection were off (the user had switched
them off), but the two remaining toggles were reported as on forever — even
after they were switched off in the UI. The stage read the wrong Defender
preferences, so the check and the UI did not talk about the same thing.

Decisions:

- **Fix the mapping, not the gate.** The stage stays manual (read → hand
  over → verify, no writes); only the values it reads change.
- **Read what the UI writes.** The four toggles map to
  `RealTimeProtectionEnabled`, `MAPSReporting`, `SubmitSamplesConsent` and
  `DisableTamperProtection`.
- **Drop the hidden preference.** `DisableBlockAtFirstSeen` ("block at
  first sight") is not a toggle of the Windows Security UI, so it is not
  read. The ReviOS playbook sets it itself once Tamper Protection is off.
- **No new dependency.** `Get-MpPreference` / `Get-MpComputerStatus` are
  already the source of truth.

## Changes

### `win/bootstrap.ps1`

1. `Get-DefenderTogglesOn` — the cloud-delivered check drops the
   `DisableBlockAtFirstSeen` term and reads `MAPSReporting -ne 0` only
   (0 = the "Microsoft Defender Antivirus cloud protection" toggle is off).
2. `Get-DefenderTogglesOn` — the sample submission check becomes
   `SubmitSamplesConsent -ne 0` (0 = "never send" = the toggle is off).
   The old `-ne 2` reported the toggle as on exactly when it was off.
3. Both checks ignore a missing preference (`$null -ne …`) instead of
   treating "not reported" as "on".

### `win/tests/Defender.Tests.ps1`

4. The fixtures use the real mapping: `MAPSReporting = 2` (on) / `0` (off),
   `SubmitSamplesConsent = 2` (on) / `0` (off), and
   `DisableBlockAtFirstSeen = $false` — the value the UI leaves behind.
5. New test "returns nothing when every toggle is off" keeps
   `DisableBlockAtFirstSeen = $false`: the regression test for the report.
6. New tests "reads the sample submission toggle as off when it never
   sends" and "ignores the hidden block-at-first-sight preference".
7. The `Disable-Defender` fixtures use the same "all off" values.

### `win/ARCHITECTURE.md`, `win/README.md`

8. The Defender section names the preference behind each toggle and states
   that `DisableBlockAtFirstSeen` is not read.
9. README names the two cloud toggles the user has to switch off.

## Verification

1. Parse `bootstrap.ps1` and `Defender.Tests.ps1` with
   `[System.Management.Automation.Language.Parser]::ParseFile` — zero parse
   errors.
2. Run `Invoke-Pester .\win\tests` — every test passes.
3. Live check on the machine that reported the bug: `Get-MpPreference`
   shows `MAPSReporting = 0`, `SubmitSamplesConsent = 0`,
   `DisableRealtimeMonitoring = True`, `DisableTamperProtection = True` →
   `Get-DefenderTogglesOn` returns nothing and the stage prints
   "Defender toggles already off; skipping."

## Notes

- The stage could never have passed on Windows 11: `DisableBlockAtFirstSeen`
  keeps its default (off) and the old check treated that as "the cloud
  toggle is on", independent of what the user did in the UI.
- `SubmitSamplesConsent` semantics: 0 = never send, 1 = safe samples
  (deprecated), 2 = always send. The UI toggle writes 2 when it is on and
  0 when it is off.
- Tamper Protection has to be off before the playbook runs, otherwise
  `Set-MpPreference` answers `0x80004001` — that part of the stage was
  right and stays.
