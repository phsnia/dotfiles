# Plan: Turn off Windows Defender (simple manual way)

Status: implemented — scripted turn-off removed, the stage is read + open the
UI + verify.

## Goal

Turn off the Defender protections the ReviOS playbook needs, with the
simplest thing that actually works: check the toggles, show them to the
user, open Windows Security, wait, check again.

Decisions:

- **Manual, not scripted.** The stage writes nothing — no `Set-MpPreference`,
  no `DisableAntiSpyware` / real-time policy keys, no Tamper Protection
  route. Tamper Protection refuses every scripted change while it is on
  (`Set-MpPreference` answers `0x80004001`, the registry write answers
  "access not allowed"), so the scripted part was dead weight on exactly the
  machines that needed it, and a silent `SilentlyContinue` next to it on the
  rest.
- **Verify first** — read the four toggles (real-time, cloud-delivered,
  sample submission, Tamper Protection), print nothing and do nothing when
  they are already off.
- **One function.** `Disable-Defender` is verify → hand over → verify;
  `Resolve-DefenderManually` merged into it and `Set-TamperProtectionOff` /
  `Set-DefenderPolicy` are deleted.
- **No self-elevation** — the helper lives inside `bootstrap.ps1`, which
  already relaunches itself via RunAs.
- **Gate, not a gatekeeper** — the debloat stage throws when a toggle is
  still on, so the TrustedUninstaller CLI never runs against a protected
  machine.

## Changes

### `win/bootstrap.ps1`

1. Deleted `Set-TamperProtectionOff` (module switch, then registry) and
   `Set-DefenderPolicy` (policy keys).
2. `Disable-Defender` now returns a result: skip when everything is off,
   otherwise print what is still on, print where the toggles live, open
   Windows Security, wait for the user (`Confirm-Step`, max 3 rounds, 1 when
   unattended) and return `Test-DefenderOff`. `Resolve-DefenderManually` is
   gone.
3. `Invoke-Debloat` calls `Disable-Defender` once and throws when it returns
   `$false`, keeping the "Debloat blocked: Windows Security toggles still
   on: …" message.

### `win/tests/Defender.Tests.ps1`

4. Loading list and assertions follow the four remaining helpers, and assert
   the three deleted ones are gone.
5. `Set-TamperProtectionOff` context removed; the scripted `Disable-Defender`
   tests (checklist call, policy write, tamper release) and the separate
   `Resolve-DefenderManually` context collapse into one `Disable-Defender`
   context: skip when off, open + wait + report `$false`, return `$true` as
   soon as the user flips the toggles, and a new **"never writes to the
   platform"** test asserting `Set-MpPreference`, `Set-ItemProperty` and
   `New-Item` are never called.
6. `Bootstrap.Tests.ps1` — `Disable-Defender` context reworked the same way
   (skip / hand over, no writes), the `Set-DefenderPolicy` mock in the
   debloat tests is gone with the command, and the loading assertion checks
   the deleted helpers stay deleted.

### `win/ARCHITECTURE.md`, `win/README.md`

7. The Defender section describes the three-step manual flow and states that
   no preference call or policy key sits behind it; README's "Turning
   Defender off" says the stage is simple and manual.

## Verification

1. Parse `bootstrap.ps1`, `Bootstrap.Tests.ps1` and `Defender.Tests.ps1` with
   `[System.Management.Automation.Language.Parser]::ParseFile` — zero parse
   errors.
2. Grep the `.ps1` files for `Set-TamperProtectionOff`, `Set-DefenderPolicy`,
   `Resolve-DefenderManually` — only the negative `Should BeNullOrEmpty`
   assertions remain.
3. Run `Invoke-Pester .\tests` — 63 tests pass (69 before; 6 scripted tests
   dropped, 1 manual guard added).
4. Live behaviour unchanged where it matters: the stage detects the toggles,
   opens Windows Security and reports honestly, and `Invoke-Debloat` still
   blocks before the CLI while a toggle is on.

## Notes

- The earlier scripted run on this machine never got past Tamper Protection:
  `Tamper Protection module switch failed: 0x80004001`,
  `Tamper Protection registry write failed: Requested registry access is
  not allowed.` — the reason the manual path is now the only path.
- Nothing keeps the toggles off across a Defender update anymore (the
  removed policy keys did that); the ReviOS playbook replaces Defender, and
  the stage re-checks before the playbook runs.
- Turning the protections off lowers the machine's security posture; the
  ReviOS playbook is expected to replace Defender afterwards.
