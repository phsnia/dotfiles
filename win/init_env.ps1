$PS_PATH = "Microsoft.PowerShell_profile.ps1"
$BASH_PATH = ".bashrc"
$USER_HOME = $HOME

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Start-Process powershell.exe `
        -Verb RunAs `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""

    exit
}

$SOURCE = Join-Path $PSScriptRoot $PS_PATH
$TARGET_DIR = Join-Path $USER_HOME "Documents\WindowsPowerShell"
$TARGET = Join-Path $TARGET_DIR $PS_PATH

New-Item -ItemType Directory -Path $TARGET_DIR -Force | Out-Null

if (Test-Path $TARGET) {
    Remove-Item -LiteralPath $TARGET -Force
}

New-Item `
    -ItemType SymbolicLink `
    -Path $TARGET `
    -Target $SOURCE | Out-Null

Write-Host ""
Write-Host "Dotfiles linked successfully." -ForegroundColor Green
Write-Host "$TARGET -> $SOURCE"

$SOURCE = Join-Path $PSScriptRoot $BASH_PATH
$TARGET = Join-Path $USER_HOME $BASH_PATH

if (Test-Path $TARGET) {
    Remove-Item -LiteralPath $TARGET -Force
}

New-Item `
    -ItemType SymbolicLink `
    -Path $TARGET `
    -Target $SOURCE | Out-Null

Write-Host ""
Write-Host "Dotfiles linked successfully." -ForegroundColor Green
Write-Host "$TARGET -> $SOURCE"
Read-Host "Enter..."
