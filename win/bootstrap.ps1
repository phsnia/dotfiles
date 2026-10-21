# bootstrap.ps1 — Windows dotfiles bootstrap
#
# Implements win/ARCHITECTURE.md: elevate, initialize scoop (git only) and
# winget, debloat, manage drivers, link the profile and verify.
# Software installation lives in install-software.ps1.
#
# The file is read top-down in four parts:
#
#   1. Configuration  - paths, URLs and the shared switches.
#   2. Helpers        - utilities the stages build on.
#   3. Stages         - one function per stage, in the order main runs them.
#   4. Entry point    - main.
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

# Load the helper scripts that live next to this one.
. (Join-Path $PSScriptRoot 'ame-cli.ps1')

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

$Config = @{
    Downloads    = Join-Path $env:USERPROFILE 'Downloads'
    StateDir     = Join-Path $env:USERPROFILE '.dotfiles'
    StateFile    = Join-Path $env:USERPROFILE '.dotfiles\bootstrap.state.json'
    ReviPlaybook = 'https://github.com/meetrevision/playbook/releases/download/26.04/Revi-PB-26.04.apbx'
    CliStandalone = 'https://github.com/Ameliorated-LLC/trusted-uninstaller-cli/releases/download/0.8.4/CLI-Standalone.zip'
    MsiCenter    = 'https://download.msi.com/uti_exe/desktop/MSI-Center.zip'
    NvidiaDriver = 'https://us.download.nvidia.com/Windows/616.56/616.56-desktop-win10-win11-64bit-international-dch-whql.exe'
}

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

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

# Write the state file that records how the bootstrap ended.
#
# @param {hashtable} State - State to store.
# @example
#   Write-StateFile -State @{ status = 'complete' }
function Write-StateFile {
    param([Parameter(Mandatory)][hashtable]$State)

    $State | ConvertTo-Json | Set-Content -Path $Config.StateFile -ErrorAction SilentlyContinue
}

# Persist a successful completion state.
#
# @example
#   Save-CompletionState
function Save-CompletionState {
    Write-StateFile -State @{
        status     = 'complete'
        finishedAt = (Get-Date).ToString('o')
        profile    = (Resolve-ProfilePath)
    }
    Write-Host "==> Completion state saved: $($Config.StateFile)"
}

# Persist recovery state on failure.
#
# @param {string} Message - Failure message.
# @example
#   Save-RecoveryState -Message "boom"
function Save-RecoveryState {
    param([string]$Message)

    Write-StateFile -State @{
        status     = 'failed'
        finishedAt = (Get-Date).ToString('o')
        error      = $Message
    }
    Write-Host "==> Recovery state saved: $($Config.StateFile)"
}

# Path of the marker file that records a finished stage.
#
# @param {string} Name - Stage name, e.g. 'debloat'.
# @return {string} Full path to the marker file.
# @example
#   Get-StageMarkerPath -Name 'debloat'
function Get-StageMarkerPath {
    param([Parameter(Mandatory)][string]$Name)

    return (Join-Path $Config.StateDir "stage-$Name.done")
}

# Check whether a stage already ran (stage marker in the state dir).
#
# @param {string} Name - Stage name, e.g. 'debloat'.
# @return {bool} True when the stage is already done.
# @example
#   if (Test-Stage 'debloat') { return }
function Test-Stage {
    param([Parameter(Mandatory)][string]$Name)

    return (Test-Path (Get-StageMarkerPath -Name $Name))
}

# Mark a stage as done so later runs skip it.
#
# @param {string} Name - Stage name, e.g. 'debloat'.
# @example
#   Complete-Stage 'debloat'
function Complete-Stage {
    param([Parameter(Mandatory)][string]$Name)

    Set-Content -Path (Get-StageMarkerPath -Name $Name) -Value (Get-Date).ToString('o') -ErrorAction SilentlyContinue
    Write-Host "==> Stage marked done: $Name"
}

# Refresh $env:Path from the registry so programs installed during this
# run (scoop, App Installer) resolve without restarting the shell.
#
# @example
#   Update-SessionPath
function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

# -----------------------------------------------------------------------------
# Stages
# -----------------------------------------------------------------------------

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

# Set the CurrentUser execution policy to RemoteSigned.
# Group Policy may enforce a policy that blocks setting the CurrentUser
# scope. The script itself runs under -ExecutionPolicy Bypass, so this only
# affects future shells.
#
# @example
#   Set-ExecutionPolicyRemoteSigned
function Set-ExecutionPolicyRemoteSigned {
    $policy = (Get-ExecutionPolicy -List -ErrorAction SilentlyContinue |
        Where-Object Scope -eq 'CurrentUser').ExecutionPolicy

    if ($policy -eq 'RemoteSigned') {
        Write-Host "==> Execution policy already RemoteSigned; skipping."
        return
    }

    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
        Write-Host "==> Execution policy set to RemoteSigned (CurrentUser)."
    } catch {
        Write-Host "==> Execution policy not set: $($_.Exception.Message)"
    }
}

# Create a directory when it is missing.
#
# @param {string} Path - Directory to create.
# @example
#   Ensure-Directory -Path $Config.StateDir
function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path $Path) {
        Write-Host "==> Directory exists: $Path"
        return
    }

    try {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Host "==> Directory created: $Path"
    } catch {
        Write-Host "==> Directory creation failed ($Path): $($_.Exception.Message)"
    }
}

# Prepare the execution environment.
# Verify: execution policy set and directories exist? Then skip.
#
# @example
#   Initialize-Environment
function Initialize-Environment {
    Write-Host "==> Initializing environment..."

    Set-ExecutionPolicyRemoteSigned

    # Verify: directories exist? Then skip.
    foreach ($dir in $Config.Downloads, $Config.StateDir) {
        Ensure-Directory -Path $dir
    }
}

# Install Scoop when it is missing, or update it when it is already there.
#
# @example
#   Install-Scoop
function Install-Scoop {
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host "==> Scoop is already installed; updating."
        scoop update
        return
    }

    # The installer kills the process when elevated unless -RunAsAdmin
    # is passed; that performs a system-wide install under ProgramData.
    Write-Host "==> Installing Scoop (all users)..."
    $installer = [scriptblock]::Create((Invoke-RestMethod -Uri 'https://get.scoop.sh'))
    & $installer -RunAsAdmin
}

# Add a Scoop bucket when it is missing.
#
# @param {string} Name - Bucket name.
# @example
#   Add-ScoopBucket -Name 'main'
function Add-ScoopBucket {
    param([Parameter(Mandatory)][string]$Name)

    if (scoop bucket list 2>$null | Select-String -SimpleMatch $Name) {
        Write-Host "==> Scoop bucket '$Name' already added; skipping."
        return
    }

    scoop bucket add $Name
}

# Install a Scoop package when it is missing.
#
# @param {string} Name - Package name.
# @example
#   Install-ScoopPackage -Name 'git'
function Install-ScoopPackage {
    param([Parameter(Mandatory)][string]$Name)

    if (scoop list $Name 2>$null | Select-String -SimpleMatch $Name) {
        Write-Host "==> Already installed (scoop): $Name"
        return
    }

    scoop install $Name
    if ($LASTEXITCODE -ne 0) { throw "scoop install failed: $Name (exit code $LASTEXITCODE)" }
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
        Install-Scoop

        # The installer only updates PATH in the registry; refresh this session.
        Update-SessionPath

        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
            throw "scoop not found on PATH after installation."
        }

        Add-ScoopBucket -Name 'main'
        Install-ScoopPackage -Name 'git'
    } catch {
        Write-Host "==> Scoop initialization failed: $($_.Exception.Message)"
        throw
    }
}

# Check whether winget resolves on PATH.
#
# @return {bool} True when winget is available.
# @example
#   if (Test-WingetAvailable) { ... }
function Test-WingetAvailable {
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

# Route 1 - let the Microsoft Store deliver App Installer.
#
# @return {bool} True when winget showed up on PATH.
# @example
#   Install-WingetFromStore
function Install-WingetFromStore {
    try {
        if (-not (Get-AppxPackage -Name Microsoft.WindowsStore -ErrorAction SilentlyContinue)) {
            Write-Host "==> Microsoft Store not present; downloading App Installer instead."
            return $false
        }

        Write-Host "==> Requesting Microsoft Store update scan..."
        $scan = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' `
            -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01' -ErrorAction Stop
        $null = Invoke-CimMethod -InputObject $scan -MethodName 'UpdateScanMethod' -ErrorAction Stop

        # The Store applies updates asynchronously; poll for winget.
        foreach ($attempt in 1..6) {
            Start-Sleep -Seconds 5
            Update-SessionPath
            if (Test-WingetAvailable) {
                Write-Host "==> winget available via the Microsoft Store."
                return $true
            }
        }

        Write-Host "==> Microsoft Store did not provide App Installer; downloading instead."
        return $false
    } catch {
        Write-Host "==> Microsoft Store repair failed: $($_.Exception.Message)"
        return $false
    }
}

# Resolve the .appx dependencies of a winget-cli release. Recent releases
# ship them as a zip archive, older ones as standalone .appx assets. The
# x64 dependencies match the machine bootstrap runs on.
#
# @param {object} Release - Release object from the GitHub API.
# @return {string[]} Paths of the dependency packages.
# @example
#   Get-AppInstallerDependencies -Release $release
function Get-AppInstallerDependencies {
    param([Parameter(Mandatory)]$Release)

    $deps = @()
    $depZip = @($Release.assets | Where-Object { $_.name -like '*Dependencies*.zip' } | Select-Object -First 1)
    if ($depZip.Count -gt 0) {
        $zip = Get-RemoteFile -Url $depZip[0].browser_download_url -Directory $Config.Downloads
        $extract = Join-Path (Split-Path $zip) ([IO.Path]::GetFileNameWithoutExtension($zip))
        if (-not (Test-Path $extract)) { Expand-Archive -Path $zip -DestinationPath $extract -Force }
        $deps = @(Get-ChildItem $extract -Recurse -Include *.appx -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match 'x64' } | ForEach-Object { $_.FullName })
    }

    if ($deps.Count -eq 0) {
        $deps = @($Release.assets | Where-Object { $_.name -like '*.appx' } |
            ForEach-Object { Get-RemoteFile -Url $_.browser_download_url -Directory $Config.Downloads })
    }

    return $deps
}

# Route 2 - install the latest winget-cli release from GitHub.
#
# @return {bool} True when winget showed up on PATH.
# @example
#   Install-WingetFromRelease
function Install-WingetFromRelease {
    try {
        Write-Host "==> Downloading the latest winget-cli release..."
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' `
            -Headers @{ 'User-Agent' = 'dotfiles-bootstrap' } -ErrorAction Stop

        $bundleAsset = @($release.assets | Where-Object { $_.name -like '*.msixbundle' } | Select-Object -First 1)
        if ($bundleAsset.Count -eq 0) { throw "no .msixbundle asset in release '$($release.tag_name)'" }
        $bundle = Get-RemoteFile -Url $bundleAsset[0].browser_download_url -Directory $Config.Downloads

        $deps = @(Get-AppInstallerDependencies -Release $release)
        if ($deps.Count -gt 0) {
            Add-AppxPackage -Path $bundle -DependencyPath $deps -ErrorAction Stop
        } else {
            Add-AppxPackage -Path $bundle -ErrorAction Stop
        }

        Update-SessionPath
        if (Test-WingetAvailable) {
            Write-Host "==> winget installed from the winget-cli release."
            return $true
        }

        Write-Host "==> winget still not on PATH after installing App Installer."
        return $false
    } catch {
        Write-Host "==> App Installer download failed: $($_.Exception.Message)"
        return $false
    }
}

# Repair winget (App Installer) when it is missing. Two routes, in order:
# 1. Microsoft Store - ask the Store to run an update scan so it can
#    deliver App Installer, polling for winget to appear.
# 2. Direct download - install the latest winget-cli .msixbundle (plus its
#    .appx dependencies) from the GitHub releases.
# Verify: winget resolves on PATH? Then skip.
#
# @example
#   Repair-Winget
function Repair-Winget {
    if (Test-WingetAvailable) {
        Write-Host "==> winget already available; nothing to repair."
        return
    }

    Write-Host "==> winget (App Installer) missing; repairing..."

    if (Install-WingetFromStore) { return }
    Install-WingetFromRelease
}

# Verify winget (App Installer) is available and refresh its sources.
# A missing winget is repaired first (Microsoft Store, then direct download).
# All winget package installs live in install-software.ps1.
# Verify: winget on PATH? Repair when missing, then skip when present.
#
# @example
#   Initialize-Winget
function Initialize-Winget {
    Write-Host "==> Initializing winget..."

    # Verify: winget already on PATH? Otherwise repair App Installer.
    if (-not (Test-WingetAvailable)) {
        Repair-Winget
    }

    # Verify again: repair may have failed - winget is needed downstream.
    if (-not (Test-WingetAvailable)) {
        throw "winget not available after repair; install 'App Installer' from the Microsoft Store."
    }

    # Best effort: refresh sources so later installs see current manifests.
    try {
        winget source update --accept-source-agreements 2>$null | Out-Null
        Write-Host "==> winget ready."
    } catch {
        Write-Host "==> winget source update failed: $($_.Exception.Message)"
    }
}

# Trust PSGallery so Install-Module never stops on the "Untrusted
# repository" confirmation.
# Verify: already trusted? Then skip.
#
# @example
#   Set-PSGalleryTrusted
function Set-PSGalleryTrusted {
    if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -eq 'Trusted') {
        Write-Host "==> PSGallery already trusted; skipping."
        return
    }

    Write-Host "==> Trusting the PSGallery repository..."
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
}

# Make sure PSWindowsUpdate and its prerequisites are available.
#
# @example
#   Initialize-WindowsUpdate
function Initialize-WindowsUpdate {
    # PowerShellGet blocks on a provider prompt when NuGet is missing;
    # install it up front so bootstrap never stops mid-run for it.
    $nuget = @(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |
        Where-Object { $_.Version -ge [version]'2.8.5.201' })
    if ($nuget.Count -eq 0) {
        Write-Host "==> Installing NuGet package provider..."
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
    }

    # Avoid the "Untrusted repository" confirmation from Install-Module.
    Set-PSGalleryTrusted

    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-Host "==> Installing PSWindowsUpdate module..."
        Install-Module PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction Stop
    }
    Import-Module PSWindowsUpdate -ErrorAction Stop
}

# Scan for pending updates. Get-WindowsUpdate can hand back a nested array;
# re-emitting each element flattens it to one update each.
#
# @return {object[]} Pending updates.
# @example
#   Get-PendingWindowsUpdates
function Get-PendingWindowsUpdates {
    return @(Get-WindowsUpdate -ErrorAction Stop | ForEach-Object { $_ })
}

# Format the size of a pending update for display.
# PSWindowsUpdate reports Size as a unit-suffixed string ("44MB", "1GB");
# older builds returned a byte count, sometimes as an array.
#
# @param {object} Update - Update object from Get-WindowsUpdate.
# @return {string} Size in MB, the raw value when unknown, or '' when absent.
# @example
#   Format-UpdateSize -Update $update
function Format-UpdateSize {
    param([Parameter(Mandatory)]$Update)

    $parts = @($Update.Size) | Where-Object { $_ -ne $null -and "$_" -ne '' }
    if ($parts.Count -eq 0) { return '' }

    $unitMb = @{ B = 1.0 / 1MB; KB = 1KB / 1MB; MB = 1.0; GB = 1024.0 }
    $sum = 0.0
    foreach ($part in $parts) {
        if ("$part" -match '^\s*([\d.,]+)\s*(B|KB|MB|GB)\s*$') {
            $sum += [double]($matches[1] -replace ',', '.') * $unitMb[$matches[2].ToUpper()]
            continue
        }

        $number = 0.0
        if ([double]::TryParse("$part", [ref]$number)) {
            $sum += $number / 1MB
            continue
        }

        # Unknown format - show the raw value instead of guessing.
        return "$($parts -join ', ')"
    }

    return ('{0:N1} MB' -f $sum)
}

# Print the pending updates.
#
# @param {object[]} Updates - Pending updates.
# @example
#   Show-PendingUpdates -Updates $updates
function Show-PendingUpdates {
    param([Parameter(Mandatory)][object[]]$Updates)

    Write-Host "==> $($Updates.Count) update(s) pending:"
    foreach ($update in $Updates) {
        $size = Format-UpdateSize -Update $update
        if ($size) {
            Write-Host ("==>   - {0} ({1})" -f $update.Title, $size)
        } else {
            Write-Host ("==>   - {0}" -f $update.Title)
        }
    }
}

# Apply Windows updates via the PSWindowsUpdate module (best effort).
# Scans first: when nothing is pending the stage is skipped, since updates
# require a reboot afterwards. One scan, one install pass - the Windows
# Update service handles the downloading itself.
#
# @example
#   Update-Windows
function Update-Windows {
    Write-Host "==> Checking Windows updates..."

    try {
        Initialize-WindowsUpdate

        $updates = @(Get-PendingWindowsUpdates)
        if ($updates.Count -eq 0) {
            Write-Host "==> Windows is already up to date; skipping update (no reboot needed)."
            return
        }

        Show-PendingUpdates -Updates $updates

        # Installing means a reboot later - let the user decide.
        if (-not (Confirm-Step "Install these updates now? (a reboot will be needed)")) {
            Write-Host "==> Windows update skipped by user; continuing without installing updates."
            return
        }

        # One serial pass downloads and installs the pending updates.
        # Installs stay serial: CBS/TrustedInstaller allows one at a time.
        Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot
        Write-Host "==> Windows update finished. Reboot required to finish installing updates."
    } catch {
        Write-Host "==> Windows update skipped: $($_.Exception.Message)"
    }
}

# -----------------------------------------------------------------------------
# Windows Defender
# -----------------------------------------------------------------------------

# Ask the user to confirm a Defender step.
#
# @param {string} Question - Prompt text.
# @return {bool} True when confirmed.
# @example
#   Confirm-DefenderStep "Real-time protection turned off?"
function Confirm-DefenderStep {
    param([Parameter(Mandatory)][string]$Question)

    if ($Unattended) {
        Write-Host "==> (unattended) auto-confirming: $Question"
        return $true
    }
    return ((Read-Host "$Question (y/N)") -eq 'y')
}

# Read the Windows Security toggles the ReviOS playbook requires off. The
# wizard checks the four toggles on Virus & threat protection > Manage
# settings: real-time, cloud-delivered, sample submission, Tamper Protection.
#
# @return {string[]} Names of the toggles that are still on.
# @example
#   Get-DefenderTogglesOn
function Get-DefenderTogglesOn {
    $on = [System.Collections.Generic.List[string]]::new()

    $status = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($status -and $status.RealTimeProtectionEnabled) { $on.Add('Real-time protection') }

    $pref = Get-MpPreference -ErrorAction SilentlyContinue
    if ($pref) {
        if (-not $pref.DisableBlockAtFirstSeen -or $pref.MAPSReporting -ne 0) { $on.Add('Cloud-delivered protection') }
        if ($pref.SubmitSamplesConsent -ne 2) { $on.Add('Automatic sample submission') }
    }

    # Tamper Protection: the module preference is authoritative, the
    # registry value is the fallback for builds without the preference.
    $tamper = $null
    if ($pref -and $null -ne $pref.DisableTamperProtection) {
        $tamper = -not $pref.DisableTamperProtection
    } else {
        $features = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features' `
            -Name 'TamperProtection' -ErrorAction SilentlyContinue
        if ($features) { $tamper = ($features.TamperProtection -ne 0) }
    }
    if ($tamper) { $on.Add('Tamper protection') }

    return $on.ToArray()
}

# Turn off Tamper Protection through the platform.
#
# Both routes fail while the platform protects the key - the module switch
# answers with 0x80004001 and the registry write with "access not allowed".
# The caller falls back to the Windows Security UI.
#
# @return {bool} True when the platform accepted the change.
# @example
#   Set-TamperProtectionOff
function Set-TamperProtectionOff {
    # Route 1 - the Defender module switch.
    try {
        Set-MpPreference -DisableTamperProtection $true -ErrorAction Stop
        Write-Host "==> Tamper Protection switched off (module)."
        return $true
    } catch {
        Write-Host "==> Tamper Protection module switch failed: $($_.Exception.Message)"
    }

    # Route 2 - the registry value.
    $path = 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features'
    try {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force -ErrorAction Stop | Out-Null
        }
        # No -Type here: Set-ItemProperty infers REG_DWORD from the integer.
        Set-ItemProperty -Path $path -Name 'TamperProtection' -Value 0 -ErrorAction Stop
        Write-Host "==> Tamper Protection switched off (registry)."
        return $true
    } catch {
        Write-Host "==> Tamper Protection registry write failed: $($_.Exception.Message)"
        return $false
    }
}

# Write the policy flags the ReviOS playbook checks for, so the protections
# stay off after a Defender update re-enables them.
#
# @example
#   Set-DefenderPolicy
function Set-DefenderPolicy {
    $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
    if (-not (Test-Path $policy)) {
        New-Item -Path $policy -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Set-ItemProperty -Path $policy -Name 'DisableAntiSpyware' -Value 1 -ErrorAction SilentlyContinue

    $rtPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'
    if (-not (Test-Path $rtPolicy)) {
        New-Item -Path $rtPolicy -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Set-ItemProperty -Path $rtPolicy -Name 'DisableRealtimeMonitoring' -Value 1 -ErrorAction SilentlyContinue
}

# Open the Windows Security page that holds the Defender toggles, so the
# user can turn off what the platform refuses to let a script touch.
#
# @return {bool} True when a page was opened.
# @example
#   Show-DefenderSettings
function Show-DefenderSettings {
    foreach ($page in @('ms-settings:windowsdefender', 'windowsdefender://threatsettings')) {
        try {
            Start-Process $page -ErrorAction Stop
            Write-Host "==> Windows Security opened ($page)."
            return $true
        } catch {
            Write-Host "==> Could not open '$page': $($_.Exception.Message)"
        }
    }

    Write-Host '==> Open Windows Security > Virus & threat protection > Manage settings by hand.'
    return $false
}

# Turn off the Defender protections the platform allows.
# Verify: all four Windows Security toggles already off? Then skip.
#
# @example
#   Disable-Defender
function Disable-Defender {
    # Verify: already disabled? Then skip.
    if (@(Get-DefenderTogglesOn).Count -eq 0) {
        Write-Host '==> Defender toggles already off; skipping.'
        return
    }

    # Tamper Protection blocks every preference write - try to release it
    # first, but expect to do it by hand.
    if (@(Get-DefenderTogglesOn) -contains 'Tamper protection') {
        Write-Host '==> Tamper Protection is on; trying to release it...'
        $null = Set-TamperProtectionOff
    }

    try {
        # Every toggle on the ReviOS checklist: real-time, behaviour/IOAV,
        # cloud-delivered (block at first sight + MAPS) and sample submission.
        Set-MpPreference -DisableRealtimeMonitoring $true `
            -DisableBehaviorMonitoring $true `
            -DisableIOAVProtection $true `
            -DisableBlockAtFirstSeen $true `
            -MAPSReporting Disabled `
            -SubmitSamplesConsent NeverSend `
            -ErrorAction Stop
    } catch {
        Write-Host "==> Could not disable Defender protections: $($_.Exception.Message)"
    }

    # Policy keys the ReviOS playbook checks for.
    Set-DefenderPolicy

    # The platform can accept the call and keep the protection on (Tamper
    # Protection does exactly that) - report what is actually off.
    if (@(Get-DefenderTogglesOn) -contains 'Real-time protection') {
        Write-Host '==> Real-time protection is still on; the platform rejected the change.'
    } else {
        Write-Host '==> Defender protections disabled.'
    }
}

# Verify that every toggle the playbook needs is off.
#
# @return {bool} True when Defender is fully off.
# @example
#   Test-DefenderOff
function Test-DefenderOff {
    return (@(Get-DefenderTogglesOn).Count -eq 0)
}

# Hand the remaining toggles to the user: open Windows Security, wait for
# the toggles to go off and check again (max 3 rounds).
#
# @return {bool} True when every toggle is off afterwards.
# @example
#   Resolve-DefenderManually
function Resolve-DefenderManually {
    $attempts = if ($Unattended) { 1 } else { 3 }

    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        $on = @(Get-DefenderTogglesOn)
        if ($on.Count -eq 0) { return $true }

        Write-Host "==> Still on: $($on -join ', ')"
        $null = Show-DefenderSettings
        if (-not (Confirm-DefenderStep 'Turn off the toggles above in Windows Security, then continue?')) { break }
    }

    return (Test-DefenderOff)
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

        # Defender must be off before the playbook is applied: the scriptable
        # part runs first, whatever the platform keeps on is handed to the
        # user in the Windows Security window.
        Disable-Defender
        if (-not (Resolve-DefenderManually)) {
            $togglesOn = @(Get-DefenderTogglesOn)
            throw "Debloat blocked: Windows Security toggles still on: $($togglesOn -join ', '). Turn them off and re-run."
        }

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

# List the present devices that are not healthy.
#
# @return {object[]} Devices with a status other than OK or Unknown.
# @example
#   Get-UnhealthyDevices
function Get-UnhealthyDevices {
    return @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' })
}

# Install the MSI OEM driver bundle.
#
# @example
#   Install-MsiDrivers
function Install-MsiDrivers {
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
}

# Install the vendor GPU driver package.
#
# @example
#   Install-NvidiaDriver
function Install-NvidiaDriver {
    $nvidia = Get-RemoteFile -Url $Config.NvidiaDriver -Directory $Config.Downloads
    Start-Process -FilePath $nvidia -ArgumentList '-s' -Wait
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
        $problems = @(Get-UnhealthyDevices)
        if ($problems.Count -eq 0) {
            Write-Host "==> All present devices healthy; skipping driver installation."
            return
        }

        foreach ($device in $problems) {
            Write-Host "==> Device issue: $($device.FriendlyName) [$($device.Status)]"
        }

        # Install MSI OEM drivers
        Install-MsiDrivers

        # Install a vendor GPU driver if needed
        if (Confirm-Step "Install the NVIDIA driver package?") {
            Install-NvidiaDriver
        }
    } catch {
        Write-Host "==> Driver installation failed: $($_.Exception.Message)"
        throw
    }

    # Verify: re-check devices after installing
    Write-Host "==> Verifying devices..."
    $problems = @(Get-UnhealthyDevices)
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

# Check whether the profile is already a symlink to the given source.
#
# @param {string} Path   - Profile path.
# @param {string} Source - Expected link target.
# @return {bool} True when the link already points at the source.
# @example
#   Test-ProfileLinked -Path $linkPath -Source $source
function Test-ProfileLinked {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source
    )

    $existing = Get-Item $Path -ErrorAction SilentlyContinue
    return ($existing -and
        $existing.LinkType -eq 'SymbolicLink' -and
        $existing.Target -contains $Source)
}

# Replace the profile with a symlink to the source.
#
# @param {string} Path   - Profile path.
# @param {string} Source - Link target.
# @example
#   Link-Profile -Path $linkPath -Source $source
function Link-Profile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source
    )

    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    if (Test-Path $Path) { Remove-Item $Path -Force }
    New-Item -ItemType SymbolicLink -Path $Path -Target $Source | Out-Null
    Write-Host "==> Linked $Path -> $Source"
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
        if (Test-ProfileLinked -Path $linkPath -Source $source) {
            Write-Host "==> Profile already linked; skipping."
        } else {
            Link-Profile -Path $linkPath -Source $source
        }

        # Verify the link
        if (-not (Test-ProfileLinked -Path $linkPath -Source $source)) {
            throw "Profile symlink verification failed."
        }
    } catch {
        Write-Host "==> Profile link failed: $($_.Exception.Message)"
        throw
    }

    Save-CompletionState
    Write-Host "==> Bootstrap complete."
}

# -----------------------------------------------------------------------------
# Entry point
# -----------------------------------------------------------------------------

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

# Run the stages only when the file is executed. Dot-sourcing it (tests,
# tooling) just defines the functions.
if ($MyInvocation.InvocationName -ne '.') {
    main
}
