# Plan: Turn off Windows Defender

Status: implemented, verified live and merged into `bootstrap.ps1` — the
standalone script was removed after the merge.

## Goal

Turn off the Defender protections the ReviOS playbook needs and verify the
result. The logic was first written as a standalone `win/turn-off-defender.ps1`
and, once it was verified on a real machine, merged into `bootstrap.ps1`; the
standalone script no longer exists.

Decisions:

- **Verify first** — read the current Defender state, print it, and do
  nothing when every toggle is already off.
- **Scripted first, by hand for the rest** — the platform refuses to let a
  script disable real-time protection while Tamper Protection is on
  (`Set-MpPreference` answers `0x80004001`, the registry write answers
  "access not allowed"). The stage does everything the platform allows,
  then opens Windows Security and waits for the user to flip the remaining
  toggles; it re-checks after every round (max 3).
- **Same knobs as the playbook checklist** — real-time, behavior/IOAV,
  cloud-delivered (block at first sight + MAPS) and sample submission go off
  through `Set-MpPreference`; `DisableAntiSpyware=1` plus the real-time
  policy key are written so the protections stay off.
- **No self-elevation** — the helpers live inside `bootstrap.ps1`, which
  already relaunches itself via RunAs.
- **Gate, not a gatekeeper** — the debloat stage throws when a toggle is
  still on, so the TrustedUninstaller CLI never runs against a protected
  machine.

## Changes

### `win/bootstrap.ps1`

1. The Defender helpers live in the "Windows Defender" section of
   `bootstrap.ps1`:
   - `Confirm-DefenderStep` — asks the user to confirm a Defender step
     (`-Unattended` auto-confirms).
   - `Get-DefenderTogglesOn` — the four toggles that are still on.
   - `Set-TamperProtectionOff` — module switch, then registry.
   - `Set-DefenderPolicy` — `DisableAntiSpyware` + real-time policy keys.
   - `Show-DefenderSettings` — opens the Windows Security page.
   - `Disable-Defender` — scripted part: release tamper protection, apply
     `Set-MpPreference`, write the policy keys.
   - `Test-DefenderOff` — verification check.
   - `Resolve-DefenderManually` — opens Windows Security, waits for the
     toggles to go off and re-checks (max 3 rounds).
   - The old standalone entry points (`Assert-DefenderAdministrator`,
     `Invoke-DefenderShutdown`) are gone — the bootstrap entry point replaces
     them.
2. `Invoke-Debloat` calls `Disable-Defender` and `Resolve-DefenderManually`
   before the playbook is applied, and throws when a toggle is still on.

### `win/tests/Defender.Tests.ps1`

3. Pester tests (Pester 3.4 style) with the Defender cmdlets mocked:
   toggle detection (module preference and registry fallback), the two
   tamper routes, the preference/policy writes, the Windows Security page
   (both URLs), the skip-when-off path, the manual fallback path and the
   final verification result. The helpers are loaded out of `bootstrap.ps1`
   via AST (name-filtered).

### `win/ARCHITECTURE.md`, `win/README.md`

4. Document the Defender stage as part of the bootstrap.

## Verification

1. Parse `bootstrap.ps1` and the test file with
   `[System.Management.Automation.Language.Parser]::ParseFile` — zero parse
   errors.
2. `Invoke-Pester win\tests\Defender.Tests.ps1` — all tests pass.
3. Live run (elevated, `-Unattended`) on this machine:

   ```
   ==> Still on: Real-time protection, Cloud-delivered protection, Automatic sample submission, Tamper protection
   ==> Tamper Protection module switch failed: Operation failed with the following error: 0x80004001
   ==> Tamper Protection registry write failed: Requested registry access is not allowed.
   ==> Turn off Tamper Protection: Windows Security > Virus & threat protection > Manage settings.
   ==> Real-time protection is still on; the platform rejected the change.
   ==> Still on: Real-time protection, Tamper protection
   === exit code: 1 ===
   ```

   The stage behaves as designed: it detects the blocker, tries both
   programmatic routes, asks for the one thing only the UI can do, applies
   everything else and reports the result honestly.

4. Live run (elevated, interactive) after the user turned **Tamper
   protection** off in Windows Security:

   ```
   ==> Still on: Real-time protection, Tamper protection
   ==> Windows Security opened (ms-settings:windowsdefender).
   ==> All Windows Security toggles are off.
   === exit code: 0 ===
   ```

   `Get-MpComputerStatus` afterwards reports `RealTimeProtectionEnabled =
   False` and `AntivirusEnabled = False`; `Get-MpPreference` answers
   `0x800106ba` (the Defender platform is disabled).
5. Integration: `Invoke-Pester win\tests` — all tests pass.

## Notes

- Tamper Protection cannot be turned off by a script while the platform
  protects it; the Windows Security UI is the only way, so the stage asks
  and waits instead of hanging.
- `Set-MpPreference -DisableTamperProtection $true` exists but fails with
  `0x80004001` while tamper protection is active.
- **Bug found in `bootstrap.ps1`**: `Set-DefenderPolicy` called
  `Set-ItemProperty ... -Type DWord`. `Set-ItemProperty` has no `-Type`
  parameter, so the write always failed - and `-ErrorAction SilentlyContinue`
  swallowed the error, so the `DisableAntiSpyware` policy was never written.
  The merged helper uses `Set-ItemProperty` without `-Type` (an integer value
  produces a REG_DWORD).
- Turning the protections off lowers the machine's security posture; the
  ReviOS playbook is expected to replace Defender afterwards.
