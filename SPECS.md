# SPECS

## win/bootstrap.ps1

### Purpose

Bootstrap the Windows environment: self-elevate, initialize Scoop, and link the
PowerShell profile into this repo.

### Interface

| Param | Type | Default | Description |
| --- | --- | --- | --- |
| `ProfilePath` | `string` | `$PROFILE.CurrentUserCurrentHost` | Profile path to link. |

### Flow

1. Print banner.
2. Check for administrator; if not elevated, relaunch the same host via
   `RunAs` and exit the original process.
3. `Initialize-Scoop` — set `ExecutionPolicy RemoteSigned` (CurrentUser),
   install Scoop if missing (else `scoop update`), add the bundled `main` bucket.
4. Symlink `$ProfilePath` → `Microsoft.PowerShell_profile.ps1` (force-replace
   anything already there).
5. Pause with `Read-Host` before closing.

### Deferred

Not yet implemented here (see `win/SPEC.md`):

- Package installs and the `extras` / `versions` buckets (require git).
- Debloat (ReviOS), driver management (MSI), software install, final verify.
