# bootstrap.ps1 — Windows dotfiles bootstrap
#
# Implements win/ARCHITECTURE.md: elevate, initialize scoop (git only) and
# winget, debloat, manage drivers, link the profile and verify.
# Software installation lives in install-software.ps1.
#
# The file is read top-down in numbered sections:
#
#   1. Configuration    - paths, URLs and the shared switches.
#   2. Helpers          - utilities the stages build on.
#   3. Environment      - execution policy and directories.
#   4. Scoop            - scoop plus git, the only package installed here.
#   5. Winget           - App Installer, repaired when it is missing.
#   6. Windows Update   - verify only: report pending updates, install none.
#   7. Windows Defender - the four toggles the ReviOS playbook needs off.
#   8. Debloat          - the ReviOS playbook.
#   9. Drivers          - OEM and vendor driver packages.
#  10. Profile          - symlink $PROFILE into this repo.
#  11. Entry point      - main.
#
# @example
#   .\bootstrap.ps1
#   .\bootstrap.ps1 -SkipUpdateCheck

[CmdletBinding()]
param(
    [string]$ProfilePath,
    [switch]$Unattended,
    [switch]$SkipUpdateCheck
)

$ErrorActionPreference = 'Stop'

# -ProfilePath is an explicit override only. When it is not passed, every
# check resolves the live $PROFILE of the session running the bootstrap.
$script:ProfilePathExplicit = $PSBoundParameters.ContainsKey('ProfilePath')

# Result of the Windows update check, saved to the state file.
$script:UpdateCheckResult = $null

# Load the helper scripts that live next to this one.
. (Join-Path $PSScriptRoot 'lib\common.ps1')
. (Join-Path $PSScriptRoot 'ame-cli.ps1')

# -----------------------------------------------------------------------------
# 1. Configuration
# -----------------------------------------------------------------------------

$Config = @{
    Downloads       = Join-Path $env:USERPROFILE 'Downloads'
    StateDir        = Join-Path $env:USERPROFILE '.dotfiles'
    StateFile       = Join-Path $env:USERPROFILE '.dotfiles\bootstrap.state.json'
    ReviPlaybook    = 'https://github.com/meetrevision/playbook/releases/download/26.04/Revi-PB-26.04.apbx'
    CliStandalone   = 'https://github.com/Ameliorated-LLC/trusted-uninstaller-cli/releases/download/0.8.4/CLI-Standalone.zip'
    MsiCenter       = 'https://download.msi.com/uti_exe/desktop/MSI-Center.zip'
    NvidiaDriver    = 'https://us.download.nvidia.com/Windows/616.56/616.56-desktop-win10-win11-64bit-international-dch-whql.exe'
    UpdateSettings  = 'ms-settings:windowsupdate'
}

# -----------------------------------------------------------------------------
# 2. Helpers
# -----------------------------------------------------------------------------

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
    $state = @{
        status     = 'complete'
        finishedAt = (Get-Date).ToString('o')
        profile    = (Resolve-ProfilePath)
    }

    # The Windows update check result, when the check ran.
    if ($script:UpdateCheckResult) { $state['windowsUpdate'] = $script:UpdateCheckResult }

    Write-StateFile -State $state
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

# Release a COM object so its handle does not stay open for the rest of
# the run.
#
# @param {object} Object - COM object to release.
# @example
#   Release-Com $session
function Release-Com {
    param([Parameter(Mandatory)]$Object)

    try {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Object)
    } catch {
        # Not a COM object (or already released) - nothing to release.
    }
}

# -----------------------------------------------------------------------------
# 3. Environment
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
    if ($SkipUpdateCheck) { $argList += ' -SkipUpdateCheck' }

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

# -----------------------------------------------------------------------------
# 4. Scoop
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# 5. Winget
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# 6. Windows Update (verify only)
# -----------------------------------------------------------------------------

# Scan for pending Windows updates through the built-in Windows Update
# client API (Microsoft.Update.Session). The scan is read-only: nothing is
# approved, downloaded or installed - approving an update is what lets the
# Windows Update client install it later on its own.
#
# @return {object[]} Pending updates with Title, Size (bytes), KB,
#                   Mandatory and Downloaded.
# @example
#   Get-PendingWindowsUpdates
function Get-PendingWindowsUpdates {
    $session = $null
    $searcher = $null
    $result = $null

    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        # IsInstalled=0 - not on the machine yet; IsHidden=0 - the ones the
        # user should see.
        $result = $searcher.Search('IsInstalled=0 and IsHidden=0')
    } catch {
        Write-Host "==> Windows Update scan failed: $($_.Exception.Message)"
        return @()
    }

    $updates = @()
    foreach ($update in @($result.Updates)) {
        $kb = @()
        try { $kb = @($update.KBArticleIDs) } catch { $kb = @() }

        # MaxDownloadSize is a 32-bit ULONG. Reading it through the COM
        # binder can carry junk in the upper bits, so the value is masked
        # back to 32 bits. An implausible size is dropped - the stage
        # reports the update, not a wrong number.
        $size = 0
        try {
            $raw = [int64]$update.MaxDownloadSize
            if ($raw -gt 4294967295) { $raw = $raw % 4294967296 }   # low 32 bits
            if ($raw -gt 0 -and $raw -le 53687091200) { $size = $raw }  # 50 GB
        } catch {
            $size = 0
        }

        $updates += [pscustomobject]@{
            Title      = "$($update.Title)"
            Size       = $(if ($size -gt 0) { $size } else { $null })
            KB         = ($kb -join ', ')
            Mandatory  = [bool]$update.IsMandatory
            Downloaded = [bool]$update.IsDownloaded
        }

        Release-Com $update
    }

    Release-Com $result
    Release-Com $searcher
    Release-Com $session

    return $updates
}

# Normalize the size of a pending update to MB.
# The update client reports the size in different shapes ('44MB', a raw
# byte count, an array of both); an unknown shape returns $null so the
# caller can fall back to the raw value.
#
# @param {object} Update - Update object.
# @return {double} Size in MB, or $null when the shape is unknown.
# @example
#   Get-UpdateSizeMb -Update $update
function Get-UpdateSizeMb {
    param([Parameter(Mandatory)]$Update)

    $parts = @($Update.Size) | Where-Object { $_ -ne $null -and "$_" -ne '' }
    if ($parts.Count -eq 0) { return $null }

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

        # Unknown format - the caller shows the raw value instead.
        return $null
    }

    return $sum
}

# Format the size of a pending update for display.
# Sizes arrive in different shapes (a unit-suffixed string like "44MB", a
# raw byte count, an array of both); an unknown format is printed as-is.
#
# @param {object} Update - Update object.
# @return {string} Size in MB, the raw value when unknown, or '' when absent.
# @example
#   Format-UpdateSize -Update $update
function Format-UpdateSize {
    param([Parameter(Mandatory)]$Update)

    $mb = Get-UpdateSizeMb -Update $Update
    if ($null -ne $mb) { return ('{0:N1} MB' -f $mb) }

    $parts = @($Update.Size) | Where-Object { $_ -ne $null -and "$_" -ne '' }
    if ($parts.Count -eq 0) { return '' }

    # Unknown format - show the raw value instead of guessing.
    return "$($parts -join ', ')"
}

# Sum the sizes of the pending updates.
#
# @param {object[]} Updates - Pending updates.
# @return {double} Total size in MB.
# @example
#   Get-UpdateSizeTotal -Updates $updates
function Get-UpdateSizeTotal {
    param([Parameter(Mandatory)][object[]]$Updates)

    $total = 0.0
    foreach ($update in $Updates) {
        $mb = Get-UpdateSizeMb -Update $update
        if ($null -ne $mb) { $total += $mb }
    }

    return $total
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
        $kb = ''
        if ($null -ne $update.KB -and "$($update.KB)" -ne '') { $kb = " (KB $($update.KB))" }

        if ($size) {
            Write-Host ("==>   - {0}{1} ({2})" -f $update.Title, $kb, $size)
        } else {
            Write-Host ("==>   - {0}{1}" -f $update.Title, $kb)
        }
    }
}

# Verify whether Windows is up to date and report the result.
# Nothing is installed: the stage never approves, downloads or installs an
# update, not even in unattended mode. Pending updates are left to the user
# - the Windows Update settings page is opened for them.
# Verify: the scan reports no pending updates? Then Windows is up to date.
#
# @example
#   Test-WindowsUpdates
function Test-WindowsUpdates {
    Write-Host "==> Checking Windows updates..."

    if ($SkipUpdateCheck) {
        Write-Host "==> Windows update check skipped (-SkipUpdateCheck)."
        $script:UpdateCheckResult = @{
            checkedAt     = (Get-Date).ToString('o')
            skipped       = $true
            upToDate      = $null
            pendingCount  = $null
            pendingSizeMb = $null
        }
        return
    }

    $updates = @(Get-PendingWindowsUpdates)

    if ($updates.Count -eq 0) {
        Write-Host "==> Windows is up to date; no pending updates."
        $script:UpdateCheckResult = @{
            checkedAt     = (Get-Date).ToString('o')
            skipped       = $false
            upToDate      = $true
            pendingCount  = 0
            pendingSizeMb = 0
        }
        return
    }

    Show-PendingUpdates -Updates $updates

    $totalMb = Get-UpdateSizeTotal -Updates $updates
    Write-Host ("==> {0} update(s) pending ({1:N1} MB); installing them is left to Windows Update." -f $updates.Count, $totalMb)

    $script:UpdateCheckResult = @{
        checkedAt     = (Get-Date).ToString('o')
        skipped       = $false
        upToDate      = $false
        pendingCount  = $updates.Count
        pendingSizeMb = [math]::Round($totalMb, 1)
    }

    # Hand the job to the user: the Windows Update page does the installing.
    if (-not $Unattended) {
        try {
            Start-Process $Config.UpdateSettings -ErrorAction Stop
            Write-Host "==> Windows Update opened ($($Config.UpdateSettings)); install the updates there."
        } catch {
            Write-Host "==> Could not open the Windows Update page: $($_.Exception.Message)"
        }
    }
}

# -----------------------------------------------------------------------------
# 7. Windows Defender
# -----------------------------------------------------------------------------

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

# Open the Windows Security page that holds the Defender toggles, so the
# user can turn them off by hand.
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

# Turn Defender off: verify, then hand the toggles to the user.
# Nothing is written - Tamper Protection refuses every scripted change
# (`Set-MpPreference` answers 0x80004001, the registry write answers
# "access not allowed"), so the stage opens Windows Security, waits for
# the toggles to go off and re-checks (max 3 rounds, 1 when unattended).
# Verify: all four Windows Security toggles already off? Then skip.
#
# @return {bool} True when every toggle is off afterwards.
# @example
#   Disable-Defender
function Disable-Defender {
    # Verify: already off? Then skip.
    if (Test-DefenderOff) {
        Write-Host '==> Defender toggles already off; skipping.'
        return $true
    }

    $attempts = if ($Unattended) { 1 } else { 3 }

    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        $on = @(Get-DefenderTogglesOn)
        if ($on.Count -eq 0) { return $true }

        Write-Host "==> Still on: $($on -join ', ')"
        Write-Host '==> Turn them off in Windows Security > Virus & threat protection > Manage settings (Tamper protection first).'
        $null = Show-DefenderSettings
        if (-not (Confirm-Step 'Turn off the toggles above in Windows Security, then continue?')) { break }
    }

    if (Test-DefenderOff) {
        Write-Host '==> Defender toggles are off.'
        return $true
    }

    Write-Host '==> Defender toggles still on.'
    return $false
}

# Verify that every toggle the playbook needs is off.
#
# @return {bool} True when Defender is fully off.
# @example
#   Test-DefenderOff
function Test-DefenderOff {
    return (@(Get-DefenderTogglesOn).Count -eq 0)
}

# -----------------------------------------------------------------------------
# 8. Debloat
# -----------------------------------------------------------------------------

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

        # Defender must be off before the playbook is applied: the playbook
        # refuses to run against a protected machine. Nothing is scripted -
        # the stage opens Windows Security and waits for the four toggles.
        if (-not (Disable-Defender)) {
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

# -----------------------------------------------------------------------------
# 9. Drivers
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# 10. Profile
# -----------------------------------------------------------------------------

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
# 11. Entry point
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
        Test-WindowsUpdates
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
