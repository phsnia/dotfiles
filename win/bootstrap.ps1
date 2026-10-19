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

# Load the TrustedUninstaller CLI helpers (same folder as this script).
. (Join-Path $PSScriptRoot 'ame-cli.ps1')

# Load configuration.
$Config = @{
    Downloads    = Join-Path $env:USERPROFILE 'Downloads'
    StateDir     = Join-Path $env:USERPROFILE '.dotfiles'
    LogFile      = Join-Path $env:USERPROFILE '.dotfiles\bootstrap.log'
    StateFile    = Join-Path $env:USERPROFILE '.dotfiles\bootstrap.state.json'
    ReviPlaybook = 'https://github.com/meetrevision/playbook/releases/download/26.04/Revi-PB-26.04.apbx'
    CliStandalone = 'https://github.com/Ameliorated-LLC/trusted-uninstaller-cli/releases/download/0.8.4/CLI-Standalone.zip'
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
    Write-Log "Stage marked done: $Name"
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
# Verify: execution policy set and directories exist? Then skip.
#
# @example
#   Initialize-Environment
function Initialize-Environment {
    Write-Log "Initializing environment..."

    # Verify: CurrentUser policy already RemoteSigned?
    $policy = (Get-ExecutionPolicy -List -ErrorAction SilentlyContinue |
        Where-Object Scope -eq 'CurrentUser').ExecutionPolicy

    if ($policy -eq 'RemoteSigned') {
        Write-Log "Execution policy already RemoteSigned; skipping."
    } else {
        # Group Policy may enforce a policy that blocks setting the
        # CurrentUser scope. The script itself runs under
        # -ExecutionPolicy Bypass, so this only affects future shells.
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
            Write-Log "Execution policy set to RemoteSigned (CurrentUser)."
        } catch {
            Write-Log "Execution policy not set: $($_.Exception.Message)" -Level WARN
        }
    }

    # Verify: directories exist? Then skip.
    foreach ($dir in $Config.Downloads, $Config.StateDir) {
        if (Test-Path $dir) {
            Write-Log "Directory exists: $dir"
        } else {
            try {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-Log "Directory created: $dir"
            } catch {
                Write-Log "Directory creation failed ($dir): $($_.Exception.Message)" -Level WARN
            }
        }
    }
}

# Install Scoop if missing (or update it) and add the bundled main bucket.
# Verify: scoop on PATH and main bucket present? Then skip.
#
# @example
#   Initialize-Scoop
function Initialize-Scoop {
    Write-Log "Initializing scoop..."

    try {
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            Write-Log "Scoop is already installed; updating."
            scoop update
        } else {
            # The installer kills the process when elevated unless -RunAsAdmin
            # is passed; that performs a system-wide install under ProgramData.
            Write-Log "Installing Scoop (all users)..."
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
            Write-Log "Scoop bucket 'main' already added; skipping."
        } else {
            scoop bucket add main
        }
    } catch {
        Write-Log "Scoop initialization failed: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

# Install Scoop-managed packages.
# Verify: each package installed? Then skip it.
# git is installed first — the extras/versions buckets are cloned with git,
# and git itself comes from the bundled `main` bucket.
#
# @example
#   Install-ScoopPackages
function Install-ScoopPackages {
    Write-Log "Installing scoop packages..."

    # git first - the other buckets are cloned with git.
    try {
        if (scoop list git 2>$null | Select-String -SimpleMatch 'git') {
            Write-Log "Already installed (scoop): git"
        } else {
            scoop install git
        }

        foreach ($bucket in 'extras', 'versions') {
            if (scoop bucket list 2>$null | Select-String -SimpleMatch $bucket) {
                Write-Log "Scoop bucket already added: $bucket"
            } else {
                scoop bucket add $bucket
            }
        }
    } catch {
        Write-Log "Scoop setup failed: $($_.Exception.Message)" -Level WARN
    }

    $packages = 'fzf', 'glazewm', 'obs-studio', 'zed', 'zellij', 'vscode', 'dotnet-sdk-lts'
    foreach ($package in $packages) {
        try {
            # Verify: package already installed? Then skip.
            if (scoop list $package 2>$null | Select-String -SimpleMatch $package) {
                Write-Log "Already installed (scoop): $package"
                continue
            }
            scoop install $package
        } catch {
            Write-Log "scoop install failed ($package): $($_.Exception.Message)" -Level WARN
        }
    }
}

# Install packages available through winget.
# Verify: package listed by winget? Then skip it.
#
# @example
#   Install-WingetPackages
function Install-WingetPackages {
    Write-Log "Installing winget packages..."

    # Browsers (Edge is kept by the playbook; Brave comes from winget)
    $packages = 'Brave.Brave',
                'BlenderFoundation.Blender.LTS.4.5',
                'xpf0000.FlyEnv',
                'JavadMotallebi.NeatDownloadManager',
                'HiBitSoftware.HiBitUninstaller',
                'Roblox.Roblox'

    foreach ($id in $packages) {
        try {
            # Verify: already installed? Then skip.
            $listed = winget list --id $id --exact --accept-source-agreements 2>$null |
                Select-String -SimpleMatch $id
            if ($listed) {
                Write-Log "Already installed (winget): $id"
                continue
            }
            winget install -e --id $id --accept-source-agreements --accept-package-agreements
        } catch {
            Write-Log "winget install failed ($id): $($_.Exception.Message)" -Level WARN
        }
    }
}

# Apply Windows updates via the PSWindowsUpdate module (best effort).
# Scans first: when nothing is pending the stage is skipped, since updates
# require a reboot afterwards.
#
# @example
#   Update-Windows
function Update-Windows {
    Write-Log "Checking Windows updates..."

    try {
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-Log "Installing PSWindowsUpdate module..."
            Install-Module PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction Stop
        }
        Import-Module PSWindowsUpdate -ErrorAction Stop

        # Scan only - do not install yet.
        $updates = @(Get-WindowsUpdate -ErrorAction Stop)

        if ($updates.Count -eq 0) {
            Write-Log "Windows is already up to date; skipping update (no reboot needed)."
            return
        }

        Write-Log "$($updates.Count) update(s) pending:"
        foreach ($update in $updates) {
            Write-Log ("  - {0} ({1:N1} MB)" -f $update.Title, ($update.Size / 1MB))
        }

        # Installing means a reboot later - let the user decide.
        if (-not (Confirm-Step "Install these updates now? (a reboot will be needed)")) {
            Write-Log "Windows update skipped by user; continuing without installing updates." -Level WARN
            return
        }

        Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot
        Write-Log "Windows update finished. Reboot required to finish installing updates."
    } catch {
        Write-Log "Windows update skipped: $($_.Exception.Message)" -Level WARN
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
        Write-Log "Defender real-time protection already off; skipping."
        return
    }

    Write-Log "Turning off Windows Defender..."

    try {
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop
        Write-Log "Real-time protection disabled."
    } catch {
        Write-Log "Could not disable real-time protection (turn off Tamper Protection manually): $($_.Exception.Message)" -Level WARN
    }

    # Policy keys the ReviOS playbook checks for.
    $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
    if (-not (Test-Path $policy)) { New-Item -Path $policy -Force | Out-Null }
    Set-ItemProperty -Path $policy -Name 'DisableAntiSpyware' -Value 1 -Type DWord -ErrorAction SilentlyContinue

    $status = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($status -and $status.RealTimeProtectionEnabled) {
        Write-Log "Defender is still on - disable Tamper Protection in Windows Security, the wizard check will fail otherwise." -Level WARN
    }
}

# Download + verify the ReviOS playbook, disable Defender and apply it
# headlessly with the TrustedUninstaller CLI.
# Verify: stage marker exists? Then skip (already applied).
#
# @example
#   Invoke-Debloat
function Invoke-Debloat {
    Write-Log "1. Debloat (ReviOS)..."

    # Verify: already applied on an earlier run?
    if (Test-Stage 'debloat') {
        Write-Log "Debloat already applied (stage marker found); skipping."
        return
    }

    try {
        # Download ReviOS playbook
        $playbook = Get-RemoteFile -Url $Config.ReviPlaybook -Directory $Config.Downloads

        # Verify source and artifact
        Write-Log "Verifying debloat artifacts..."
        if (-not (Test-Artifact -Path $playbook)) {
            throw "Playbook artifact is missing or empty."
        }

        # Defender must be off before the playbook is applied.
        Disable-Defender

        if (-not (Confirm-Step "Apply the ReviOS playbook now via the TrustedUninstaller CLI?")) {
            Write-Log "Debloat skipped by user; continuing without applying the playbook." -Level WARN
            return
        }

        # Apply via CLI: no wizard, no clicking. The option IDs reproduce the
        # wizard selections (disable Defender, disable Hibernate, remove all
        # apps, General configuration all + remove pinned items; Edge kept,
        # Brave installed via winget later).
        Invoke-ReviCli -CliZipUrl $Config.CliStandalone -PlaybookUrl $Config.ReviPlaybook
    } catch {
        Write-Log "Debloat failed: $($_.Exception.Message)" -Level ERROR
        throw
    }

    Complete-Stage 'debloat'
    Write-Log "Debloat complete."
}

# Detect hardware, install OEM/vendor drivers and verify devices.
# Verify: all present devices healthy? Then skip.
#
# @example
#   Invoke-Drivers
function Invoke-Drivers {
    Write-Log "2. Driver management (MSI laptop)..."

    try {
        # Detect model and hardware
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        Write-Log "Detected: $($cs.Manufacturer) $($cs.Model)"

        # Verify: nothing wrong with devices? Then skip driver installs.
        $problems = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' })

        if ($problems.Count -eq 0) {
            Write-Log "All present devices healthy; skipping driver installation."
            return
        }

        foreach ($device in $problems) {
            Write-Log "Device issue: $($device.FriendlyName) [$($device.Status)]" -Level WARN
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
        Write-Log "Driver installation failed: $($_.Exception.Message)" -Level ERROR
        throw
    }

    # Verify: re-check devices after installing
    Write-Log "Verifying devices..."
    $problems = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' })

    if ($problems.Count -gt 0) {
        foreach ($device in $problems) {
            Write-Log "Device issue: $($device.FriendlyName) [$($device.Status)]" -Level WARN
        }
        if (-not (Confirm-Step "Continue despite device issues?")) {
            Write-Log "Device issues noted; continuing by user choice." -Level WARN
            return
        }
    } else {
        Write-Log "All devices healthy."
    }

    Write-Log "Driver installation complete."
}

# Install Scoop/winget packages and run downloaded installers.
# Verify: all expected commands on PATH? Then skip.
#
# @example
#   Install-Software
function Install-Software {
    Write-Log "3. Software installation..."

    # Verify: everything already installed? Then skip.
    $missing = @('git', 'fzf', 'zed', 'code') |
        Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) }

    if ($missing.Count -eq 0) {
        Write-Log "All expected software already installed; skipping."
    } else {
        Write-Log "Missing software: $($missing -join ', ')"

        try {
            # Install scoop + winget packages (each verifies per package)
            Install-ScoopPackages
            Install-WingetPackages
        } catch {
            Write-Log "Package installation failed: $($_.Exception.Message)" -Level WARN
        }

        # Download external files
        $external = @(
            (Get-RemoteFile -Url $Config.QtEmu -Directory $Config.Downloads)
        )

        # Run installers, handling each artifact type
        foreach ($file in $external) {
            switch ([IO.Path]::GetExtension($file).ToLower()) {
                { $_ -in '.exe', '.msi' } {
                    if (Test-Artifact -Path $file) {
                        try { Start-Process -FilePath $file -Wait }
                        catch { Write-Log "Installer failed ($file): $($_.Exception.Message)" -Level WARN }
                    } else {
                        Write-Log "Installer missing: $file" -Level WARN
                    }
                }
                default {
                    Write-Log "Unhandled artifact type: $file" -Level WARN
                }
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
# Verify: profile already a symlink to the repo? Then skip.
#
# @example
#   Complete-Bootstrap
function Complete-Bootstrap {
    Write-Log "4. Link and verify..."

    $source = Join-Path $PSScriptRoot 'Microsoft.PowerShell_profile.ps1'

    try {
        # Verify: link already correct? Then skip.
        $existing = Get-Item $ProfilePath -ErrorAction SilentlyContinue
        $alreadyLinked = $existing -and
            $existing.LinkType -eq 'SymbolicLink' -and
            $existing.Target -contains $source

        if ($alreadyLinked) {
            Write-Log "Profile already linked; skipping."
        } else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath) -Force | Out-Null
            if (Test-Path $ProfilePath) { Remove-Item $ProfilePath -Force }
            New-Item -ItemType SymbolicLink -Path $ProfilePath -Target $source | Out-Null
            Write-Log "Linked $ProfilePath -> $source"
        }

        # Verify the link
        $link = Get-Item $ProfilePath -ErrorAction SilentlyContinue
        if (-not ($link -and $link.LinkType -eq 'SymbolicLink')) {
            throw "Profile symlink verification failed."
        }
    } catch {
        Write-Log "Profile link failed: $($_.Exception.Message)" -Level ERROR
        throw
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
        if (-not $Unattended) { Write-Host 'Press Enter to close' -NoNewline; $null = Read-Host }
    }
}

main
