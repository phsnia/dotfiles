# Plan: Replace Write-Log with simple `==>` output

Status: implemented

## Goal

Drop the timestamped/leveled `Write-Log` system (console + log file) in favor of
plain `Write-Host "==> ..."` lines. Console-only output; no log file.

Decisions:

- All messages use the same `==>` prefix — no colors, no level tags, no
  timestamps. Message wording already conveys skip/fail status.
- `~\.dotfiles\bootstrap.log` is removed entirely.

## Changes

### `win/bootstrap.ps1`

1. Delete the `Write-Log` function (lines 34–53), `$script:LogFile` (line 16),
   and the `LogFile` entry in `$Config` (line 25).
2. Replace all ~70 `Write-Log "..." [-Level X]` calls with
   `Write-Host "==> ..."`. The `-Level WARN/ERROR` arguments disappear.
3. Start routine: drop `$script:LogFile = $Config.LogFile` and the
   `Set-Content ... "=== bootstrap started ..."` header write.
4. `Save-RecoveryState`: drop the `log = $script:LogFile` key from the state
   JSON.
5. Final failure footer: keep `Bootstrap failed or needs attention.` and
   remove `See $script:LogFile`.

### `win/ame-cli.ps1`

6. Remove the fallback `Write-Log` definition (lines 17–20, guarded by
   `Get-Command Write-Log`). Replace its 5 call sites with
   `Write-Host "==> ..."`.

### `win/Debloat.Tests.ps1`

7. Remove the `Mock Write-Log` (line 70) — mocking a deleted function errors.
   Remove `LogFile` from the test config (line 21). No assertions depend on
   log output; the 4 tests stay as-is.

### `win/ARCHITECTURE.md`

8. Line 110: `Save Logs and Recovery State` → `Save Recovery State`.
9. Line 31: "save the logs and recovery state" → "save the recovery state".

`SPECS.md` and `win/README.md` have no log references; no edits needed.

## Verification

1. Parse `bootstrap.ps1`, `ame-cli.ps1`, and `Debloat.Tests.ps1` with
   `[System.Management.Automation.Language.Parser]::ParseFile` — zero parse
   errors.
2. Grep `win/` for `Write-Log` and `LogFile` — zero matches remain.
3. Run `Invoke-Pester win\Debloat.Tests.ps1` — all 4 tests pass.
