# bootstrap.ps1 — Windows dotfiles bootstrap
#
# Implements win/ARCHITECTURE.md: elevate, initialize, debloat, manage drivers,
# install software, link the profile and verify.
#
# @example
#   .\bootstrap.ps1

[CmdletBinding()]
param(
    [string]$ProfilePath = $PROFILE.CurrentUserCurrentHost,
    [switch]$Unattended
)

$ErrorActionPreference = 'Stop'
$script:LogFile = $null

# Load configuration.
$Config = @{
    Downloads    = Join-Path $env:USERPROFILE 'Downloads'
    StateDir     = Join-Path $env:USERPROFILE '.dotfiles'
    LogFile      = Join-Path $env:USERPROFILE '.dotfiles\bootstrap.log'
    StateFile    = Join-Path $env:USERPROFILE '.dotfiles\bootstrap.state.json'
    ReviPlaybook = 'https://github.com/meetrevision/playbook/releases/download/26.04/Revi-PB-26.04.apbx'
    AmeWizard    = 'https://github.com/Ameliorated-LLC/trusted-uninstaller-cli/releases/download/0.8.4/AME-Beta-v0.8.4.exe'
    MsiCenter    = 'https://download.msi.com/uti_exe/desktop/MSI-Center.zip'
    NvidiaDriver = 'https://us.download.nvidia.com/Windows/616.56/616.56-desktop-win10-win11-64bit-international-dch-whql.exe'
    QtEmu        = 'https://github.com/MateuszKrawczuk/QtEmu/releases/download/2.1.1/qtemu.exe'
}

# Write a timestamped line to the console and the log file.
#
# @param {string} Message - Line to write.
# @param {string} Level   - INFO | WARN | ERROR.
# @example
#   Write-Log "Starting" -Level INFO
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $color = switch ($Level) { 'WARN' { 'Yellow' } 'ERROR' { 'Red' } default { 'Gray' } }
    Write-Host $line -ForegroundColor $color

    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $line -ErrorAction SilentlyContinue
    }
}

# Download a file if it is not already present.
#
# @param {string} Url       - Remote URL.
# @param {string} Directory - Destination directory.
# @return {string} Full path to the downloaded file.
# @example
#   Get-RemoteFile -Url $Config.QtEmu -Directory $Config.Downloads
function Get-RemoteFile {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Directory
    )

    $fileName = Split-Path $Url -Leaf
    $output = Join-Path $Directory $fileName

    if (Test-Path $output) {
        Write-Log "Already downloaded: $fileName"
        return $output
    }

    Write-Log "Downloading: $fileName"
    curl.exe -L $Url -o $output
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url" }

    return $output
}

# Verify an artifact exists and is non-empty.
#
# @param {string} Path - File to verify.
# @return {bool} True when the artifact is usable.
# @example
#   Test-Artifact -Path $file
function Test-Artifact {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) { return $false }
    if ((Get-Item $Path).Length -eq 0) { return $false }
    return $true
}

# Ask the user to confirm an interactive step.
#
# @param {string} Question - Prompt text.
# @return {bool} True when confirmed.
# @example
#   Confirm-Step "Was the playbook applied?"
function Confirm-Step {
    param([Parameter(Mandatory)][string]$Question)

    if ($Unattended) {
        Write-Log "(unattended) auto-confirming: $Question"
        return $true
    }
    return ((Read-Host "$Question (y/N)") -eq 'y')
}

# Persist a successful completion state.
#
# @example
#   Save-CompletionState
function Save-CompletionState {
    @{ status = 'complete'; finishedAt = (Get-Date).ToString('o'); profile = $ProfilePath } |
        ConvertTo-Json | Set-Content -Path $Config.StateFile -ErrorAction SilentlyContinue
    Write-Log "Completion state saved: $($Config.StateFile)"
}

# Persist recovery state on failure.
#
# @param {string} Message - Failure message.
# @example
#   Save-RecoveryState -Message "boom"
function Save-RecoveryState {
    param([string]$Message)

    @{ status = 'failed'; finishedAt = (Get-Date).ToString('o'); error = $Message; log = $script:LogFile } |
        ConvertTo-Json | Set-Content -Path $Config.StateFile -ErrorAction SilentlyContinue
    Write-Log "Recovery state saved: $($Config.StateFile)" -Level ERROR
}

# Print the banner and start logging.
#
# @example
#   Start-Bootstrap
function Start-Bootstrap {
    Write-Host "==> Bootstrapping..." -ForegroundColor Cyan

    New-Item -ItemType Directory -Path $Config.StateDir -Force | Out-Null
    $script:LogFile = $Config.LogFile
    Set-Content -Path $script:LogFile -Value "=== bootstrap started $(Get-Date -Format o) ===" -ErrorAction SilentlyContinue

    Write-Log "Bootstrap started."
}

# Ensure the script is elevated, relaunching the same host via RunAs if not.
#
# @example
#   Assert-Administrator
function Assert-Administrator {
    $admin = (
        [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($admin) { return }

    # Relaunch this host, not powershell.exe, so $PROFILE stays pwsh's.
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ProfilePath `"$ProfilePath`""
    if ($Unattended) { $argList += ' -Unattended' }

    Write-Log "Not elevated; relaunching as administrator..."
    Start-Process (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList
    exit
}

# Prepare the execution environment.
#
# @example
#   Initialize-Environment
function Initialize-Environment {
    Write-Log "Initializing environment..."

    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    New-Item -ItemType Directory -Path $Config.Downloads -Force | Out-Null
    New-Item -ItemType Directory -Path $Config.StateDir -Force | Out-Null
}

# Install Scoop if missing (or update it) and add the bundled main bucket.
#
# @example
#   Initialize-Scoop
function Initialize-Scoop {
    Write-Log "Initializing scoop..."

    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Log "Scoop is already installed."
        scoop update
    } else {
        Write-Log "Installing Scoop..."
        Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
    }

    scoop bucket add main
}

# Install Scoop-managed packages.
# git is installed first — the extras/versions buckets are cloned with git,
# and git itself comes from the bundled `main` bucket.
#
# @example
#   Install-ScoopPackages
function Install-ScoopPackages {
    Write-Log "Installing scoop packages..."

    scoop install git

    scoop bucket add extras
    scoop bucket add versions

    # Tools
    scoop install fzf
    scoop install glazewm
    scoop install obs-studio
    scoop install zed

    # Programming
    scoop install zellij
    scoop install vscode
    scoop install dotnet-sdk-lts
}

# Install packages available through winget.
#
# @example
#   Install-WingetPackages
function Install-WingetPackages {
    Write-Log "Installing winget packages..."

    winget install -e --id Brave.Brave
    winget install -e --id BlenderFoundation.Blender.LTS.4.5
    winget install -e --id xpf0000.FlyEnv
    winget install -e --id JavadMotallebi.NeatDownloadManager
    winget install -e --id HiBitSoftware.HiBitUninstaller
    winget install -e --id Roblox.Roblox
}

# Apply Windows updates via the PSWindowsUpdate module (best effort).
#
# @example
#   Update-Windows
function Update-Windows {
    Write-Log "Updating Windows..."

    try {
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-Log "Installing PSWindowsUpdate module..."
            Install-Module PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction Stop
        }
        Import-Module PSWindowsUpdate -ErrorAction Stop
        Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot
        Write-Log "Windows update finished."
    } catch {
        Write-Log "Windows update skipped: $($_.Exception.Message)" -Level WARN
    }
}

# Download + verify the ReviOS playbook, run the AME Wizard and apply it.
#
# @example
#   Invoke-Debloat
function Invoke-Debloat {
    Write-Log "1. Debloat (ReviOS)..."

    # Download ReviOS playbook and the AME Wizard
    $playbook = Get-RemoteFile -Url $Config.ReviPlaybook -Directory $Config.Downloads
    $ame = Get-RemoteFile -Url $Config.AmeWizard -Directory $Config.Downloads

    # Verify source and artifact
    Write-Log "Verifying debloat artifacts..."
    if (-not (Test-Artifact -Path $playbook) -or -not (Test-Artifact -Path $ame)) {
        throw "Debloat artifacts are missing or empty."
    }

    # Invoke AME Wizard
    Write-Log "Launching AME Wizard..."
    Start-Process -FilePath $ame

    # Apply the playbook (automatic if supported, otherwise the user applies it)
    Write-Log "In AME Wizard, load '$playbook' and apply it."
    if (-not (Confirm-Step "Was the ReviOS playbook applied successfully?")) {
        throw "ReviOS playbook was not applied."
    }

    Write-Log "Debloat complete."
}

# Detect hardware, install OEM/vendor drivers and verify devices.
#
# @example
#   Invoke-Drivers
function Invoke-Drivers {
    Write-Log "2. Driver management (MSI laptop)..."

    # Detect model and hardware
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    Write-Log "Detected: $($cs.Manufacturer) $($cs.Model)"

    # Install MSI OEM drivers
    $msi = Get-RemoteFile -Url $Config.MsiCenter -Directory $Config.Downloads
    if ($msi -like '*.zip') {
        $extract = Join-Path (Split-Path $msi) ([IO.Path]::GetFileNameWithoutExtension($msi))
        if (-not (Test-Path $extract)) { Expand-Archive -Path $msi -DestinationPath $extract -Force }
        $installer = Get-ChildItem $extract -Recurse -Include *.exe, *.msi -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($installer) { Start-Process -FilePath $installer.FullName -Wait }
    } elseif (Test-Path $msi) {
        Start-Process -FilePath $msi -Wait
    }

    # Install a vendor GPU driver if needed
    if (Confirm-Step "Install the NVIDIA driver package?") {
        $nvidia = Get-RemoteFile -Url $Config.NvidiaDriver -Directory $Config.Downloads
        Start-Process -FilePath $nvidia -ArgumentList '-s' -Wait
    }

    # Verify devices
    Write-Log "Verifying devices..."
    $problems = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' }

    if ($problems) {
        foreach ($device in $problems) {
            Write-Log "Device issue: $($device.FriendlyName) [$($device.Status)]" -Level WARN
        }
        if (-not (Confirm-Step "Continue despite device issues?")) {
            throw "Required devices are not working."
        }
    }

    Write-Log "Driver installation complete."
}

# Install Scoop/winget packages and run downloaded installers.
#
# @example
#   Install-Software
function Install-Software {
    Write-Log "3. Software installation..."

    # Install scoop + winget packages
    Install-ScoopPackages
    Install-WingetPackages

    # Download external files
    $external = @(
        (Get-RemoteFile -Url $Config.QtEmu -Directory $Config.Downloads)
    )

    # Run installers, handling each artifact type
    foreach ($file in $external) {
        switch ([IO.Path]::GetExtension($file).ToLower()) {
            { $_ -in '.exe', '.msi' } {
                if (Test-Artifact -Path $file) { Start-Process -FilePath $file -Wait }
                else { Write-Log "Installer missing: $file" -Level WARN }
            }
            default {
                Write-Log "Unhandled artifact type: $file" -Level WARN
            }
        }
    }

    # Verify software installation
    foreach ($command in 'git', 'fzf', 'zed', 'code') {
        if (Get-Command $command -ErrorAction SilentlyContinue) {
            Write-Log "Verified: $command"
        } else {
            Write-Log "Missing after install: $command" -Level WARN
        }
    }

    Write-Log "Software installation complete."
}

# Link the PowerShell profile, verify it and save completion state.
#
# @example
#   Complete-Bootstrap
function Complete-Bootstrap {
    Write-Log "4. Link and verify..."

    # Create profile symlink
    $source = Join-Path $PSScriptRoot 'Microsoft.PowerShell_profile.ps1'
    New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath) -Force | Out-Null
    if (Test-Path $ProfilePath) { Remove-Item $ProfilePath -Force }
    New-Item -ItemType SymbolicLink -Path $ProfilePath -Target $source | Out-Null
    Write-Log "Linked $ProfilePath -> $source"

    # Final verification
    $link = Get-Item $ProfilePath -ErrorAction SilentlyContinue
    if (-not ($link -and $link.LinkType -eq 'SymbolicLink')) {
        throw "Profile symlink verification failed."
    }

    Save-CompletionState
    Write-Host "Bootstrap complete." -ForegroundColor Green
}

# Entry point: run each stage in order and handle failures.
#
# @example
#   main
function main {
    try {
        Start-Bootstrap
        Assert-Administrator
        Initialize-Environment
        Initialize-Scoop
        Update-Windows
        Invoke-Debloat
        Invoke-Drivers
        Install-Software
        Complete-Bootstrap
    } catch {
        Write-Log "ERROR: $($_.Exception.Message)" -Level ERROR
        Save-RecoveryState -Message $_.Exception.Message
        Write-Host "Bootstrap failed or needs attention. See $script:LogFile" -ForegroundColor Red
        if (-not $Unattended) { Read-Host 'Press Enter to close' }
        exit 1
    }

    if (-not $Unattended) { Read-Host 'Press Enter to close' }
}

main
