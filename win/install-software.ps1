# install-software.ps1 — software installation
#
# Split out of bootstrap.ps1: bootstrap only initializes scoop (git) and
# winget; this script installs the actual software. Follows the same
# verify-first contract as win/ARCHITECTURE.md — every component checks its
# own end state and skips work that is already done.
#
# Run it as a normal user after bootstrap.ps1; no elevation required.
#
# @example
#   .\install-software.ps1
#   .\install-software.ps1 -Unattended

[CmdletBinding()]
param([switch]$Unattended)

$ErrorActionPreference = 'Stop'

# Load the shared helpers that live next to this script.
. (Join-Path $PSScriptRoot 'lib\common.ps1')

# Load configuration.
$Config = @{
    Downloads   = Join-Path $env:USERPROFILE 'Downloads'
    StateDir    = Join-Path $env:USERPROFILE '.dotfiles'
    StateFile   = Join-Path $env:USERPROFILE '.dotfiles\software.state.json'
    PackageFile = Join-Path $PSScriptRoot 'package.txt'
    QtEmu       = 'https://github.com/MateuszKrawczuk/QtEmu/releases/download/2.1.1/qtemu.exe'
}

# Full inventory of managed software for this run (see Add-SoftwareRecord).
$script:Software = [System.Collections.Generic.List[object]]::new()

# Record a package's state so the run can be audited later.
#
# @param {string} Name   - Package or artifact name.
# @param {string} Tool   - scoop, winget or installer.
# @param {string} Result - installed, already-present or failed.
# @example
#   Add-SoftwareRecord -Name 'fzf' -Tool 'scoop' -Result 'installed'
function Add-SoftwareRecord {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Tool,
        [Parameter(Mandatory)][string]$Result
    )

    $script:Software.Add(@{
        name   = $Name
        tool   = $Tool
        result = $Result
        at     = (Get-Date).ToString('o')
    })
}

# Persist the full software inventory to the state file.
#
# @example
#   Save-SoftwareState
function Save-SoftwareState {
    New-Item -ItemType Directory -Path $Config.StateDir -Force | Out-Null
    ConvertTo-Json -InputObject @($script:Software) | Set-Content -Path $Config.StateFile
    Write-Host "==> Software state saved: $($Config.StateFile)"
}

# Check whether scoop has a complete install of a package.
# `scoop list` still lists a failed install, so use `scoop prefix`, which
# fails until the package has a `current` directory.
#
# @param {string} Name - Scoop package name.
# @return {bool} True when the package is installed.
# @example
#   if (Test-ScoopPackage 'git') { ... }
function Test-ScoopPackage {
    param([string]$Name)
    scoop prefix $Name *> $null
    $LASTEXITCODE -eq 0
}

# Read the package ids for one tool from package.txt.
#
# @param {string} Tool - scoop or winget.
# @return {string[]} Package ids in file order.
# @example
#   Get-PackageList -Tool scoop
function Get-PackageList {
    param([string]$Tool)
    foreach ($line in Get-Content $Config.PackageFile) {
        if ($line.Trim() -match "^$Tool\s+(\S.*)$") { $Matches[1].Trim() }
    }
}

# Install Scoop-managed packages.
# Verify: each package installed? Then skip it.
# git is checked first — the extras/versions buckets are cloned with git
# (bootstrap already installs git from the bundled `main` bucket).
#
# @example
#   Install-ScoopPackages
function Install-ScoopPackages {
    Write-Host "==> Installing scoop packages..."

    try {
        # git first - the other buckets are cloned with git.
        if (Test-ScoopPackage 'git') {
            Write-Host "==> Already installed (scoop): git"
            Add-SoftwareRecord -Name 'git' -Tool 'scoop' -Result 'already-present'
        } else {
            scoop install git
            if ($LASTEXITCODE -ne 0) {
                Add-SoftwareRecord -Name 'git' -Tool 'scoop' -Result 'failed'
                throw "scoop install failed: git (exit code $LASTEXITCODE)"
            }
            Add-SoftwareRecord -Name 'git' -Tool 'scoop' -Result 'installed'
        }

        foreach ($bucket in 'extras', 'versions', 'java') {
            if (scoop bucket list 2>$null | Select-String -SimpleMatch $bucket) {
                Write-Host "==> Scoop bucket already added: $bucket"
            } else {
                scoop bucket add $bucket
                if ($LASTEXITCODE -ne 0) { Write-Host "==> scoop bucket add failed: $bucket (exit code $LASTEXITCODE)" }
            }
        }
    } catch {
        Write-Host "==> Scoop setup failed: $($_.Exception.Message)"
    }

    $packages = Get-PackageList -Tool scoop
    foreach ($package in $packages) {
        try {
            # Verify: package already installed? Then skip.
            if (Test-ScoopPackage $package) {
                Write-Host "==> Already installed (scoop): $package"
                Add-SoftwareRecord -Name $package -Tool 'scoop' -Result 'already-present'
                continue
            }
            scoop install $package
            if ($LASTEXITCODE -ne 0) { throw "scoop exit code $LASTEXITCODE" }
            Add-SoftwareRecord -Name $package -Tool 'scoop' -Result 'installed'
        } catch {
            Write-Host "==> scoop install failed ($package): $($_.Exception.Message)"
            Add-SoftwareRecord -Name $package -Tool 'scoop' -Result 'failed'
        }
    }
}

# Install packages available through winget.
# Verify: package listed by winget? Then skip it.
#
# @example
#   Install-WingetPackages
function Install-WingetPackages {
    Write-Host "==> Installing winget packages..."

    # Browsers (Edge is kept by the playbook; Brave comes from winget)
    $packages = Get-PackageList -Tool winget

    foreach ($id in $packages) {
        try {
            # Verify: already installed? Then skip.
            $listed = winget list --id $id --exact --accept-source-agreements 2>$null |
                Select-String -SimpleMatch $id
            if ($listed) {
                Write-Host "==> Already installed (winget): $id"
                Add-SoftwareRecord -Name $id -Tool 'winget' -Result 'already-present'
                continue
            }
            winget install -e --id $id --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -ne 0) { throw "winget exit code $LASTEXITCODE" }
            Add-SoftwareRecord -Name $id -Tool 'winget' -Result 'installed'
        } catch {
            Write-Host "==> winget install failed ($id): $($_.Exception.Message)"
            Add-SoftwareRecord -Name $id -Tool 'winget' -Result 'failed'
        }
    }
}

# Install scoop/winget packages and run downloaded installers.
#
# @example
#   Install-Software
function Install-Software {
    Write-Host "==> Software installation..."

    try {
        # Each package verifies its own state, so always check the whole list.
        Install-ScoopPackages
        Install-WingetPackages
    } catch {
        Write-Host "==> Package installation failed: $($_.Exception.Message)"
    }

    # Verify: expected commands on PATH? Then skip the downloaded installers.
    $missing = @('git', 'fzf', 'zed', 'code') |
        Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) }

    if ($missing.Count -eq 0) {
        Write-Host "==> All expected commands present; skipping installers."
    } else {
        Write-Host "==> Missing software: $($missing -join ', ')"

        # Download external files
        $external = @(
            (Get-RemoteFile -Url $Config.QtEmu -Directory $Config.Downloads)
        )

        # Run installers, handling each artifact type
        foreach ($file in $external) {
            switch ([IO.Path]::GetExtension($file).ToLower()) {
                { $_ -in '.exe', '.msi' } {
                    $name = Split-Path $file -Leaf
                    if (Test-Artifact -Path $file) {
                        try {
                            Start-Process -FilePath $file -Wait
                            Add-SoftwareRecord -Name $name -Tool 'installer' -Result 'installed'
                        } catch {
                            Write-Warning "Installer failed ($file): $($_.Exception.Message)"
                            Add-SoftwareRecord -Name $name -Tool 'installer' -Result 'failed'
                        }
                    } else {
                        Write-Host "==> Installer missing: $file"
                        Add-SoftwareRecord -Name $name -Tool 'installer' -Result 'failed'
                    }
                }
                default {
                    Write-Host "==> Unhandled artifact type: $file"
                }
            }
        }
    }

    # Verify software installation
    foreach ($command in 'git', 'fzf', 'zed', 'code') {
        if (Get-Command $command -ErrorAction SilentlyContinue) {
            Write-Host "==> Verified: $command"
        } else {
            Write-Host "==> Missing after install: $command"
        }
    }

    Write-Host "==> Software installation complete."
}

# Entry point: verify the bootstrap ran, then install everything.
#
# @example
#   main
function main {
    # Verify: scoop and winget initialized by bootstrap.ps1? Then proceed.
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Host "==> scoop not found on PATH; run bootstrap.ps1 first."
        if (-not $Unattended) { Write-Host 'Press Enter to close' -NoNewline; $null = Read-Host }
        return
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "==> winget not found on PATH; run bootstrap.ps1 first."
        if (-not $Unattended) { Write-Host 'Press Enter to close' -NoNewline; $null = Read-Host }
        return
    }

    try {
        Write-Host "==> Installing software..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $Config.Downloads, $Config.StateDir -Force | Out-Null
        Install-Software
    } catch {
        Write-Host "==> $($_.Exception.Message)"
        Write-Warning "Software installation failed or needs attention."
    } finally {
        # Always persist the inventory, even after a failure.
        Save-SoftwareState

        $installed = @($script:Software | Where-Object result -eq 'installed').Count
        $present   = @($script:Software | Where-Object result -eq 'already-present').Count
        $failed    = @($script:Software | Where-Object result -eq 'failed').Count
        Write-Host "==> Software summary: $installed installed, $present already present, $failed failed."
        if (-not $Unattended) { Write-Host 'Press Enter to close' -NoNewline; $null = Read-Host }
    }
}

main
