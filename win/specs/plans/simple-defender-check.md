# Plan: Simple Windows Defender check

Status: implemented

## Goal

The Defender stage of the bootstrap was heavier than it had to be: a
`Confirm-Step` prompt (y/N), a loop of up to three rounds and a
`Disable-Defender` wrapper around it. The stage only ever reads the state
and hands the toggles to the user, so the flow is reduced to the simple
one:

```
==> Checking Windows Defender...
==> Still on: Real-time protection, Tamper protection
==> Turn them off in Windows Security > Virus & threat protection > Manage settings (Tamper protection first).
==> Press Enter to check again
==> Windows Defender is off.
```

Decisions:

- **Stay in `bootstrap.ps1`.** One script owns the whole Windows setup; the
  check is a stage of the bootstrap, not a separate tool.
- **One round, no prompt loop.** The stage opens Windows Security, waits for
  Enter and checks again — once. The user drives the toggles, the stage only
  reports the result.
- **Read the same four toggles.** Real-time, cloud-delivered, sample
  submission and Tamper Protection — the scope the ReviOS playbook needs.
- **Never write to the platform.** Tamper Protection refuses every scripted
  change, so the stage only reads and reports.
- **`-Unattended` reports only.** No window is opened and nobody is waited
  for, so the toggles stay as they are and the debloat is blocked.

## Changes

### `win/bootstrap.ps1`

1. `Disable-Defender` is deleted; `Invoke-DefenderCheck` replaces it:
   verify → hand over (open Windows Security, wait for Enter) → verify again.
   It returns `$true` only when every toggle is off afterwards.
2. `Get-DefenderTogglesOn`, `Show-DefenderSettings` and `Test-DefenderOff`
   stay as they are — they already read the correct preferences.
3. `Invoke-Debloat` calls `Invoke-DefenderCheck -Unattended:$Unattended` and
   throws the same "Debloat blocked: Windows Security toggles still on: …"
   message when a toggle is still on.
4. The section map keeps the Defender stage as section 7 (Debloat, Drivers,
   Profile and Entry point shift back to 8–11).

### `win/tests/Defender.Tests.ps1`

5. The `Disable-Defender` context becomes an `Invoke-DefenderCheck` context:
   skips the hand-over when everything is off, opens Windows Security and
   waits for Enter, returns `$true` as soon as the toggles are off, reports
   only in unattended mode and never writes to the platform.
6. `Read-Host` is mocked instead of `Confirm-Step`.

### `win/tests/Bootstrap.Tests.ps1`

7. The `Disable-Defender` context is gone — the check is covered by
   `Defender.Tests.ps1`.
8. The debloat context mocks `Invoke-DefenderCheck` (`$true` for the happy
   path, `$false` for "blocks before the CLI when the Defender toggles stay
   on") and asserts that the check runs exactly once.
9. The loading assertions drop `Disable-Defender` and require
   `Invoke-DefenderCheck`.

### `win/ARCHITECTURE.md`, `win/README.md`

10. The Defender section describes the one-round flow and the unattended
    behaviour; the flow diagram drops "max 3 tries".

## Verification

1. Parse every `win/**/*.ps1` with
   `[System.Management.Automation.Language.Parser]::ParseFile` — zero parse
   errors.
2. Run `Invoke-Pester .\win\tests` — 69 tests, all pass.
3. Live check on the machine: `Invoke-DefenderCheck -Unattended` reports
   "Windows Defender is off; nothing to do." (all four toggles are off) and
   returns `$true`.

## Notes

- The stage was already manual — the old `Disable-Defender` never wrote to
  the platform either. Only the flow got simpler.
- One round means a user who needs two attempts has to re-run the stage.
  That is the price of the simple flow; the debloat stays blocked until the
  toggles are off.
- `Test-DefenderOff` is kept as the helper that answers "is Defender
  fully off?" for the checks that do not need the hand-over.
