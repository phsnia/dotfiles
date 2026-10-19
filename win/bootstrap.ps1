# bootstrap.ps1 — Windows dotfiles bootstrap
#
# Implements win/ARCHITECTURE.md: elevate, initialize scoop (git only) and
# winget, debloat, manage drivers, link the profile and verify.
# Software installation lives in install-software.ps1.
#
# @example
#   .\bootstrap.ps1

[CmdletBinding()]
param(
    [string]$ProfilePath,
    [switch]$Unattended
)

$ErrorActionPreference = 'Stop'

# -ProfilePath is an explicit override only. When it is not passed, every
# check resolves the live $PROFILE of the session running the bootstrap.
$script:ProfilePathExplicit = $PSBoundParameters.ContainsKey('ProfilePath')

# Load the TrustedUninstaller CLI helpers (same folder as this script).
. (Join-Path $PSScriptRoot 'ame-cli.ps1')

# Load configuration.
$Config = @{
    Downloads    = Join-Path $env:USERPROFILE 'Downloads'
    StateDir     = Join-Path $env:USERPROFILE '.dotfiles'
    StateFile    = Join-Path $env:USERPROFILE '.dotfiles\bootstrap.state.json'
    ReviPlaybook = 'https://github.com/meetrevision/playbook/releases/download/26.04/Revi-PB-26.04.apbx'
    CliStandalone = 'https://github.com/Ameliorated-LLC/trusted-uninstaller-cli/releases/download/0.8.4/CLI-Standalone.zip'
    MsiCenter    = 'https://download.msi.com/uti_exe/desktop/MSI-Center.zip'
    NvidiaDriver = 'https://us.download.nvidia.com/Windows/616.56/616.56-desktop-win10-win11-64bit-international-dch-whql.exe'
}

# Download a file if it is not already present.
#
# @param {string} Url       - Remote URL.
# @param {string} Directory - Destination directory.
# @return {string} Full path to the downloaded file.
# @example
#   Get-RemoteFile -Url $Config.MsiCenter -Directory $Config.Downloads
function Get-RemoteFile {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Directory
    )

    $fileName = Split-Path $Url -Leaf
    $output = Join-Path $Directory $fileName

    if (Test-Path $output) {
        Write-Host "==> Already downloaded: $fileName"
        return $output
    }

    Write-Host "==> Downloading: $fileName"
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
        Write-Host "==> (unattended) auto-confirming: $Question"
        return $true
    }
    return ((Read-Host "$Question (y/N)") -eq 'y')
}

# Resolve the profile path to link: the -ProfilePath argument when it was
# passed explicitly, otherwise the live $PROFILE of the session running the
# bootstrap (whatever host and scope that happens to be).
#
# @return {string} Full path to the profile for this host and scope.
# @example
#   Resolve-ProfilePath
function Resolve-ProfilePath {
    if ($script:ProfilePathExplicit -and $ProfilePath) { return $ProfilePath }
    # Bare $PROFILE is a PSObject with attached path properties, not a
    # string; CurrentUserCurrentHost is the live default path.
    return $PROFILE.CurrentUserCurrentHost
}

# Persist a successful completion state.
#
# @example
#   Save-CompletionState
function Save-CompletionState {
    @{ status = 'complete'; finishedAt = (Get-Date).ToString('o'); profile = (Resolve-ProfilePath) } |
        ConvertTo-Json | Set-Content -Path $Config.StateFile -ErrorAction SilentlyContinue
    Write-Host "==> Completion state saved: $($Config.StateFile)"
}

# Persist recovery state on failure.
#
# @param {string} Message - Failure message.
# @example
#   Save-RecoveryState -Message "boom"
function Save-RecoveryState {
    param([string]$Message)

    @{ status = 'failed'; finishedAt = (Get-Date).ToString('o'); error = $Message } |
        ConvertTo-Json | Set-Content -Path $Config.StateFile -ErrorAction SilentlyContinue
    Write-Host "==> Recovery state saved: $($Config.StateFile)"
}

# Check whether a stage already ran (stage marker in the state dir).
#
# @param {string} Name - Stage name, e.g. 'debloat'.
# @return {bool} True when the stage is already done.
# @example
#   if (Test-Stage 'debloat') { return }
function Test-Stage {
    param([Parameter(Mandatory)][string]$Name)
    Test-Path (Join-Path $Config.StateDir "stage-$Name.done")
}

# Mark a stage as done so later runs skip it.
#
# @param {string} Name - Stage name, e.g. 'debloat'.
# @example
#   Complete-Stage 'debloat'
function Complete-Stage {
    param([Parameter(Mandatory)][string]$Name)
    Set-Content -Path (Join-Path $Config.StateDir "stage-$Name.done") -Value (Get-Date).ToString('o') -ErrorAction SilentlyContinue
    Write-Host "==> Stage marked done: $Name"
}

# Print the banner and prepare the state directory.
#
# @example
#   Start-Bootstrap
function Start-Bootstrap {
    Write-Host "==> Bootstrapping..." -ForegroundColor Cyan

    New-Item -ItemType Directory -Path $Config.StateDir -Force | Out-Null

    Write-Host "==> Bootstrap started."
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
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($script:ProfilePathExplicit) { $argList += " -ProfilePath `"$ProfilePath`"" }
    if ($Unattended) { $argList += ' -Unattended' }

    Write-Host "==> Not elevated; relaunching as administrator..."
    Start-Process (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList
    exit
}

# Prepare the execution environment.
# Verify: execution policy set and directories exist? Then skip.
#
# @example
#   Initialize-Environment
function Initialize-Environment {
    Write-Host "==> Initializing environment..."

    # Verify: CurrentUser policy already RemoteSigned?
    $policy = (Get-ExecutionPolicy -List -ErrorAction SilentlyContinue |
        Where-Object Scope -eq 'CurrentUser').ExecutionPolicy

    if ($policy -eq 'RemoteSigned') {
        Write-Host "==> Execution policy already RemoteSigned; skipping."
    } else {
        # Group Policy may enforce a policy that blocks setting the
        # CurrentUser scope. The script itself runs under
        # -ExecutionPolicy Bypass, so this only affects future shells.
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
            Write-Host "==> Execution policy set to RemoteSigned (CurrentUser)."
        } catch {
            Write-Host "==> Execution policy not set: $($_.Exception.Message)"
        }
    }

    # Verify: directories exist? Then skip.
    foreach ($dir in $Config.Downloads, $Config.StateDir) {
        if (Test-Path $dir) {
            Write-Host "==> Directory exists: $dir"
        } else {
            try {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-Host "==> Directory created: $dir"
            } catch {
                Write-Host "==> Directory creation failed ($dir): $($_.Exception.Message)"
            }
        }
    }
}

# Install Scoop if missing (or update it), add the bundled main bucket and
# install git — the only package bootstrap installs. Everything else comes
# from install-software.ps1.
# Verify: scoop on PATH, main bucket present, git installed? Then skip.
#
# @example
#   Initialize-Scoop
function Initialize-Scoop {
    Write-Host "==> Initializing scoop..."

    try {
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            Write-Host "==> Scoop is already installed; updating."
            scoop update
        } else {
            # The installer kills the process when elevated unless -RunAsAdmin
            # is passed; that performs a system-wide install under ProgramData.
            Write-Host "==> Installing Scoop (all users)..."
            $installer = [scriptblock]::Create((Invoke-RestMethod -Uri 'https://get.scoop.sh'))
            & $installer -RunAsAdmin
        }

        # The installer only updates PATH in the registry; refresh this session.
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                    [Environment]::GetEnvironmentVariable('Path', 'User')

        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
            throw "scoop not found on PATH after installation."
        }

        # Verify: main bucket already added?
        if (scoop bucket list 2>$null | Select-String -SimpleMatch 'main') {
            Write-Host "==> Scoop bucket 'main' already added; skipping."
        } else {
            scoop bucket add main
        }

        # git only — every other package is installed by install-software.ps1.
        if (scoop list git 2>$null | Select-String -SimpleMatch 'git') {
            Write-Host "==> Already installed (scoop): git"
        } else {
            scoop install git
            if ($LASTEXITCODE -ne 0) { throw "scoop install failed: git (exit code $LASTEXITCODE)" }
        }
    } catch {
        Write-Host "==> Scoop initialization failed: $($_.Exception.Message)"
        throw
    }
}

# Verify winget (App Installer) is available and refresh its sources.
# All winget package installs live in install-software.ps1.
# Verify: winget on PATH? Then skip.
#
# @example
#   Initialize-Winget
function Initialize-Winget {
    Write-Host "==> Initializing winget..."

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget not found on PATH; install 'App Installer' from the Microsoft Store."
    }

    # Best effort: refresh sources so later installs see current manifests.
    try {
        winget source update --accept-source-agreements 2>$null | Out-Null
        Write-Host "==> winget ready."
    } catch {
        Write-Host "==> winget source update failed: $($_.Exception.Message)"
    }
}

# Apply Windows updates via the PSWindowsUpdate module (best effort).
# Scans first: when nothing is pending the stage is skipped, since updates
# require a reboot afterwards.
#
# @example
#   Update-Windows
function Update-Windows {
    Write-Host "==> Checking Windows updates..."

    try {
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-Host "==> Installing PSWindowsUpdate module..."
            Install-Module PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction Stop
        }
        Import-Module PSWindowsUpdate -ErrorAction Stop

        # Scan only - do not install yet.
        $updates = @(Get-WindowsUpdate -ErrorAction Stop)

        if ($updates.Count -eq 0) {
            Write-Host "==> Windows is already up to date; skipping update (no reboot needed)."
            return
        }

        Write-Host "==> $($updates.Count) update(s) pending:"
        foreach ($update in $updates) {
            Write-Host ("==>   - {0} ({1:N1} MB)" -f $update.Title, ($update.Size / 1MB))
        }

        # Installing means a reboot later - let the user decide.
        if (-not (Confirm-Step "Install these updates now? (a reboot will be needed)")) {
            Write-Host "==> Windows update skipped by user; continuing without installing updates."
            return
        }

        Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot
        Write-Host "==> Windows update finished. Reboot required to finish installing updates."
    } catch {
        Write-Host "==> Windows update skipped: $($_.Exception.Message)"
    }
}

# Turn off Windows Defender protection before the playbook runs.
# Verify: real-time protection already off? Then skip.
# Tamper Protection blocks these writes; it must be turned off manually first.
#
# @example
#   Disable-Defender
function Disable-Defender {
    # Verify: already disabled? Then skip.
    $status = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($status -and -not $status.RealTimeProtectionEnabled) {
        Write-Host "==> Defender real-time protection already off; skipping."
        return
    }

    Write-Host "==> Turning off Windows Defender..."

    try {
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop
        Write-Host "==> Real-time protection disabled."
    } catch {
        Write-Host "==> Could not disable real-time protection (turn off Tamper Protection manually): $($_.Exception.Message)"
    }

    # Policy keys the ReviOS playbook checks for.
    $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
    if (-not (Test-Path $policy)) { New-Item -Path $policy -Force | Out-Null }
    Set-ItemProperty -Path $policy -Name 'DisableAntiSpyware' -Value 1 -Type DWord -ErrorAction SilentlyContinue

    $status = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($status -and $status.RealTimeProtectionEnabled) {
        Write-Host "==> Defender is still on - disable Tamper Protection in Windows Security, the wizard check will fail otherwise."
    }
}

# Download + verify the ReviOS playbook, disable Defender and apply it
# headlessly with the TrustedUninstaller CLI.
# Verify: stage marker exists? Then skip (already applied).
#
# @example
#   Invoke-Debloat
function Invoke-Debloat {
    Write-Host "==> 1. Debloat (ReviOS)..."

    # Verify: already applied on an earlier run?
    if (Test-Stage 'debloat') {
        Write-Host "==> Debloat already applied (stage marker found); skipping."
        return
    }

    try {
        # Download ReviOS playbook
        $playbook = Get-RemoteFile -Url $Config.ReviPlaybook -Directory $Config.Downloads

        # Verify source and artifact
        Write-Host "==> Verifying debloat artifacts..."
        if (-not (Test-Artifact -Path $playbook)) {
            throw "Playbook artifact is missing or empty."
        }

        # Defender must be off before the playbook is applied.
        Disable-Defender

        if (-not (Confirm-Step "Apply the ReviOS playbook now via the TrustedUninstaller CLI?")) {
            Write-Host "==> Debloat skipped by user; continuing without applying the playbook."
            return
        }

        # Apply via CLI: no wizard, no clicking. The option IDs reproduce the
        # wizard selections (disable Defender, disable Hibernate, remove all
        # apps, General configuration all + remove pinned items; Edge kept,
        # Brave installed later via install-software.ps1).
        Invoke-ReviCli -CliZipUrl $Config.CliStandalone -PlaybookUrl $Config.ReviPlaybook
    } catch {
        Write-Host "==> Debloat failed: $($_.Exception.Message)"
        throw
    }

    Complete-Stage 'debloat'
    Write-Host "==> Debloat complete."
}

# Detect hardware, install OEM/vendor drivers and verify devices.
# Verify: all present devices healthy? Then skip.
#
# @example
#   Invoke-Drivers
function Invoke-Drivers {
    Write-Host "==> 2. Driver management (MSI laptop)..."

    try {
        # Detect model and hardware
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        Write-Host "==> Detected: $($cs.Manufacturer) $($cs.Model)"

        # Verify: nothing wrong with devices? Then skip driver installs.
        $problems = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' })

        if ($problems.Count -eq 0) {
            Write-Host "==> All present devices healthy; skipping driver installation."
            return
        }

        foreach ($device in $problems) {
            Write-Host "==> Device issue: $($device.FriendlyName) [$($device.Status)]"
        }

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
    } catch {
        Write-Host "==> Driver installation failed: $($_.Exception.Message)"
        throw
    }

    # Verify: re-check devices after installing
    Write-Host "==> Verifying devices..."
    $problems = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' })

    if ($problems.Count -gt 0) {
        foreach ($device in $problems) {
            Write-Host "==> Device issue: $($device.FriendlyName) [$($device.Status)]"
        }
        if (-not (Confirm-Step "Continue despite device issues?")) {
            Write-Host "==> Device issues noted; continuing by user choice."
            return
        }
    } else {
        Write-Host "==> All devices healthy."
    }

    Write-Host "==> Driver installation complete."
}

# Link the PowerShell profile, verify it and save completion state.
# Verify: profile already a symlink to the repo? Then skip.
#
# @example
#   Complete-Bootstrap
function Complete-Bootstrap {
    Write-Host "==> 3. Link and verify..."

    # Check and link against the live $PROFILE of this session (or the
    # explicit -ProfilePath override), not a path captured at script start.
    $linkPath = Resolve-ProfilePath
    $source = Join-Path $PSScriptRoot 'Microsoft.PowerShell_profile.ps1'

    try {
        # Verify: link already correct? Then skip.
        $existing = Get-Item $linkPath -ErrorAction SilentlyContinue
        $alreadyLinked = $existing -and
            $existing.LinkType -eq 'SymbolicLink' -and
            $existing.Target -contains $source

        if ($alreadyLinked) {
            Write-Host "==> Profile already linked; skipping."
        } else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $linkPath) -Force | Out-Null
            if (Test-Path $linkPath) { Remove-Item $linkPath -Force }
            New-Item -ItemType SymbolicLink -Path $linkPath -Target $source | Out-Null
            Write-Host "==> Linked $linkPath -> $source"
        }

        # Verify the link
        $link = Get-Item $linkPath -ErrorAction SilentlyContinue
        if (-not ($link -and $link.LinkType -eq 'SymbolicLink')) {
            throw "Profile symlink verification failed."
        }
    } catch {
        Write-Host "==> Profile link failed: $($_.Exception.Message)"
        throw
    }

    Save-CompletionState
    Write-Host "==> Bootstrap complete."
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
        Initialize-Winget
        Update-Windows
        Invoke-Debloat
        Invoke-Drivers
        Complete-Bootstrap
    } catch {
        Write-Host "==> $($_.Exception.Message)"
        Save-RecoveryState -Message $_.Exception.Message
        Write-Host "Bootstrap failed or needs attention."
    } finally {
        if (-not $Unattended) { Write-Host 'Press Enter to close' -NoNewline; $null = Read-Host }
    }
}

main
