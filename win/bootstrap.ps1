# bootstrap.ps1 — Windows dotfiles bootstrap
#
# Relaunches elevated, initializes Scoop (init only), then links $PROFILE
# to Microsoft.PowerShell_profile.ps1 in this directory.
#
# @param {string} ProfilePath - Profile to link; defaults to $PROFILE.CurrentUserCurrentHost.
# @example
#   .\bootstrap.ps1

param([string]$ProfilePath = $PROFILE.CurrentUserCurrentHost)

Write-Host "==> Boostraping..."

$admin = (
    [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $admin) {
    # Relaunch this host, not powershell.exe, so $PROFILE stays pwsh's.
    Start-Process (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList `
        "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ProfilePath `"$ProfilePath`""
    exit
}

# Initialize Scoop so its tools are available early. Install only —
# package installs and the extras/versions buckets are merged in later.
#
# @example
#   Initialize-Scoop
function Initialize-Scoop {
    Write-Host "-> Initializing scoop..."

    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host "Scoop is already installed."
        scoop update
    } else {
        Write-Host "Installing Scoop..."
        Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
    }

    # --- BUCKETS ---
    # Only the bundled `main` bucket here; extras/versions are added later.
    scoop bucket add main
}

Initialize-Scoop

try {
    Write-Host "-> Checking powershell..."
    Write-Host "   Profile: $ProfilePath"

    $source = Join-Path $PSScriptRoot "Microsoft.PowerShell_profile.ps1"
    New-Item -ItemType Directory (Split-Path -Parent $ProfilePath) -Force | Out-Null
    if (Test-Path $ProfilePath) { Remove-Item $ProfilePath -Force }
    New-Item -ItemType SymbolicLink -Path $ProfilePath -Target $source | Out-Null

    Write-Host ""
    Write-Host "Dotfiles linked successfully." -ForegroundColor Green
    Write-Host "$ProfilePath -> $source"
}
catch {
    Write-Host ""
    Write-Host "Bootstrap failed: $($_.Exception.Message)" -ForegroundColor Red
}

Read-Host "Press Enter to close"