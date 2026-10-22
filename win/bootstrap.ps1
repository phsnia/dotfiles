# bootstrap.ps1 — Windows dotfiles bootstrap
# Elevates, patches Windows, initializes scoop (git) and winget, debloats,
# installs drivers and links the profile. Software: install-software.ps1.
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
. (Join-Path $PSScriptRoot 'lib\common.ps1')
. (Join-Path $PSScriptRoot 'lib\ame-cli.ps1')

# --- Configuration -----------------------------------------------------------

$Config = @{
    Downloads       = Join-Path $env:USERPROFILE 'Downloads'
    StateDir        = Join-Path $env:USERPROFILE '.dotfiles'
    StateFile       = Join-Path $env:USERPROFILE '.dotfiles\bootstrap.state.json'
    ReviPlaybook    = 'https://github.com/meetrevision/playbook/releases/download/26.04/Revi-PB-26.04.apbx'
    CliStandalone   = 'https://github.com/Ameliorated-LLC/trusted-uninstaller-cli/releases/download/0.8.4/CLI-Standalone.zip'
    MsiCenter       = 'https://download.msi.com/uti_exe/desktop/MSI-Center.zip'
    NvidiaDriver    = 'https://us.download.nvidia.com/Windows/616.56/616.56-desktop-win10-win11-64bit-international-dch-whql.exe'
    UpdateSettings  = 'ms-settings:windowsupdate'
    UpdateMaxRounds = 5
}

# --- Support -----------------------------------------------------------------

# Ask the user to confirm an interactive step.
#
# @param {string} Question - Prompt shown to the user.
# @return {bool} True when confirmed; always true with -Unattended.
# @example
#   Confirm-Step "Install these updates now?"
function Confirm-Step {
    param([string]$Question)
    if ($Unattended) { Write-Host "==> (unattended) auto-confirming: $Question"; return $true }
    (Read-Host "$Question (y/N)") -eq 'y'
}

# Persist the bootstrap state file.
#
# @param {hashtable} State - State to write as JSON.
# @example
#   Write-StateFile -State @{ status = 'failed' }
function Write-StateFile {
    param([hashtable]$State)
    $State | ConvertTo-Json | Set-Content -Path $Config.StateFile -ErrorAction SilentlyContinue
}

# Refresh the session PATH from the registry so new programs resolve.
#
# @example
#   Update-SessionPath
function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

# Release a COM object without failing on non-COM input.
#
# @param {object} Object - COM object to release.
# @example
#   Release-Com $searcher
function Release-Com {
    param([AllowNull()]$Object)
    if ($null -eq $Object) { return }
    try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Object) } catch { }
}

# --- Environment -------------------------------------------------------------

# Ensure the script is elevated, relaunching the same host via RunAs if not.
#
# @example
#   Assert-Administrator
function Assert-Administrator {
    $user = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if ($user.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }

    # Relaunch the same host so $PROFILE stays pwsh's.
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($ProfilePath) { $argList += " -ProfilePath `"$ProfilePath`"" }
    if ($Unattended) { $argList += ' -Unattended' }
    if ($SkipUpdateCheck) { $argList += ' -SkipUpdateCheck' }
    Write-Host "==> Not elevated; relaunching as administrator..."
    Start-Process (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList
    exit
}

# Set the CurrentUser execution policy and create the work directories.
#
# @example
#   Initialize-Environment
function Initialize-Environment {
    Write-Host "==> Initializing environment..."

    $policy = (Get-ExecutionPolicy -List -ErrorAction SilentlyContinue |
        Where-Object Scope -eq 'CurrentUser').ExecutionPolicy
    if ($policy -ne 'RemoteSigned') {
        try { Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop; Write-Host "==> Execution policy set to RemoteSigned (CurrentUser)." }
        catch { Write-Host "==> Execution policy not set: $($_.Exception.Message)" }
    }

    $missing = @(@($Config.Downloads, $Config.StateDir) | Where-Object { -not (Test-Path $_) })
    if ($missing.Count -eq 0) { Write-Host "==> Directories already exist; skipping."; return }
    try { New-Item -ItemType Directory -Path $missing -Force | Out-Null; Write-Host "==> Directory created: $($missing -join ', ')" }
    catch { Write-Host "==> Directory creation failed: $($_.Exception.Message)" }
}

# --- Scoop -------------------------------------------------------------------

# Install Scoop if missing (or update it), add the main bucket and install git.
#
# @example
#   Initialize-Scoop
function Initialize-Scoop {
    Write-Host "==> Initializing scoop..."
    if (Get-Command scoop -ErrorAction SilentlyContinue) { scoop update }
    else {
        # The installer needs -RunAsAdmin when elevated; that installs for all users.
        Write-Host "==> Installing Scoop (all users)..."
        & ([scriptblock]::Create((Invoke-RestMethod -Uri 'https://get.scoop.sh'))) -RunAsAdmin
    }
    Update-SessionPath
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { throw "scoop not found on PATH after installation." }
    if (-not (scoop bucket list 2>$null | Select-String -SimpleMatch 'main')) { scoop bucket add main }
    # `scoop prefix` fails for a broken or failed install, so those are retried.
    scoop prefix git *> $null
    if ($LASTEXITCODE -eq 0) { Write-Host "==> Already installed (scoop): git"; return }
    scoop install git
    if ($LASTEXITCODE -ne 0) { throw "scoop install failed: git (exit code $LASTEXITCODE)" }
}

# --- Winget ------------------------------------------------------------------

# Check whether winget resolves on PATH.
#
# @return {bool} True when winget is available.
# @example
#   if (Test-WingetAvailable) { ... }
function Test-WingetAvailable {
    [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

# Install the latest winget-cli release from GitHub.
#
# @return {bool} True when winget is on PATH afterwards.
# @example
#   Install-WingetFromRelease
function Install-WingetFromRelease {
    try {
        $release = Invoke-RestMethod 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' `
            -Headers @{ 'User-Agent' = 'dotfiles-bootstrap' } -ErrorAction Stop
        $bundle = @($release.assets | Where-Object name -like '*.msixbundle')[0]
        if (-not $bundle) { throw "no .msixbundle asset in release '$($release.tag_name)'" }
        $bundlePath = Get-RemoteFile -Url $bundle.browser_download_url -Directory $Config.Downloads

        # Recent releases zip the .appx dependencies; older ones ship them as assets.
        $zip = @($release.assets | Where-Object name -like '*Dependencies*.zip')[0]
        if ($zip) {
            $zipPath = Get-RemoteFile -Url $zip.browser_download_url -Directory $Config.Downloads
            $dir = Join-Path (Split-Path $zipPath) ([IO.Path]::GetFileNameWithoutExtension($zipPath))
            if (-not (Test-Path $dir)) { Expand-Archive -Path $zipPath -DestinationPath $dir -Force }
            $deps = @(Get-ChildItem $dir -Recurse -Include *.appx -ErrorAction SilentlyContinue |
                Where-Object FullName -match 'x64' | ForEach-Object FullName)
        }
        if (-not $deps) {
            $deps = @($release.assets | Where-Object name -like '*.appx' |
                ForEach-Object { Get-RemoteFile -Url $_.browser_download_url -Directory $Config.Downloads })
        }

        if ($deps) { Add-AppxPackage -Path $bundlePath -DependencyPath $deps -ErrorAction Stop }
        else { Add-AppxPackage -Path $bundlePath -ErrorAction Stop }
        Update-SessionPath
        if (Test-WingetAvailable) { Write-Host "==> winget installed from the winget-cli release."; return $true }
        Write-Host "==> winget still not on PATH after installing App Installer."
        return $false
    } catch {
        Write-Host "==> App Installer download failed: $($_.Exception.Message)"
        return $false
    }
}

# Verify winget (App Installer), repairing it from the release when missing.
#
# @example
#   Initialize-Winget
function Initialize-Winget {
    Write-Host "==> Initializing winget..."
    if (-not (Test-WingetAvailable)) {
        Write-Host "==> winget (App Installer) missing; repairing..."
        Install-WingetFromRelease | Out-Null
    }
    if (-not (Test-WingetAvailable)) { throw "winget not available after repair; install 'App Installer' from the Microsoft Store." }
    winget source update --accept-source-agreements 2>$null | Out-Null
    Write-Host "==> winget ready."
}

# --- Windows Update ----------------------------------------------------------

# Scan for pending Windows updates through the Windows Update client API.
#
# @return {hashtable} Session, Searcher, Result and Updates of the scan.
# @example
#   $search = Search-WindowsUpdates
function Search-WindowsUpdates {
    $session = $null; $searcher = $null
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        # Target Microsoft Update, so a managed server does not hold the scan back.
        try { $searcher.ServerSelection = 2; $searcher.ServiceID = '7971F918-A847-4430-9279-4A52D1EFE18D' }
        catch { Write-Host '==> Microsoft Update target refused; using the configured update source.' }

        $result = $searcher.Search('IsInstalled=0 and IsHidden=0')
    } catch {
        Release-Com $searcher; Release-Com $session
        throw "Windows Update scan failed: $($_.Exception.Message)"
    }
    @{ Session = $session; Searcher = $searcher; Result = $result; Updates = $result.Updates }
}

# Summarize one pending update for the report.
#
# @param {object} Update - Update object from the scan.
# @return {pscustomobject} UpdateID, Title, KB and SizeMb.
# @example
#   Get-UpdateSummary -Update $update
function Get-UpdateSummary {
    param($Update)
    $summary = [pscustomobject]@{ UpdateID = ''; Title = ''; SizeMb = $null; KB = '' }
    try {
        $summary.UpdateID = "$($Update.UpdateID)"; $summary.Title = "$($Update.Title)"
        $summary.KB = @($Update.KBArticleIDs) -join ', '
        # MaxDownloadSize is 32-bit; the COM binder may set the upper bits.
        $size = [int64]$Update.MaxDownloadSize % 4294967296
        if ($size -gt 0) { $summary.SizeMb = $size / 1MB }
    } catch {
        # A property the client does not expose: the summary stays partial.
    }
    $summary
}

# Download and install the updates of a scan.
#
# @param {hashtable} Search    - Result of Search-WindowsUpdates.
# @param {object[]}  Summaries - Display summaries for the result report.
# @return {object[]} One result per update.
# @example
#   Install-WindowsUpdates -Search $search -Summaries $summaries
#
# Installs stay serial: CBS/TrustedInstaller holds an exclusive servicing lock.
function Install-WindowsUpdates {
    param($Search, [object[]]$Summaries = @())
    $session = $Search.Session
    $updates = $Search.Updates

    foreach ($update in @($updates)) {
        try { if (-not $update.EulaAccepted) { $update.AcceptEula() } }
        catch { Write-Host "==> Could not accept the license of an update: $($_.Exception.Message)" }
    }

    $downloader = $null
    try {
        Write-Host '==> Downloading the pending updates...'
        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $updates
        $null = $downloader.Download()
    } catch { Write-Host "==> Download failed: $($_.Exception.Message)" }
    finally { Release-Com $downloader }

    $names = @{}
    foreach ($summary in @($Summaries)) { if ($summary.UpdateID) { $names[$summary.UpdateID] = $summary } }

    $installer = $null
    $installResult = $null
    try {
        Write-Host '==> Installing the updates (this can take several minutes)...'
        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $updates
        $installResult = $installer.Install()
    } catch { Write-Host "==> Install failed: $($_.Exception.Message)"; return @() }
    finally { Release-Com $installer }

    $results = foreach ($result in @($installResult)) {
        $id = "$($result.UpdateID)"
        $summary = $names[$id]
        $code = [int]$result.ResultCode
        [pscustomobject]@{
            Title          = if ($summary) { $summary.Title } else { $id }
            KB             = if ($summary) { $summary.KB } else { '' }
            ResultCode     = $code
            HResult        = [int]$result.HResult
            RebootRequired = [bool]$result.RebootRequired
            # 2 = succeeded, 3 = succeeded with errors.
            Succeeded      = ($code -eq 2 -or $code -eq 3)
        }
        Release-Com $result
    }
    Release-Com $installResult
    $results
}

# Check whether Windows needs a reboot before the next update can land.
#
# @param {object[]} Results - Install results of the round.
# @return {bool} True when a reboot is pending.
# @example
#   Test-RebootRequired -Results $results
function Test-RebootRequired {
    param([object[]]$Results = @())
    foreach ($result in @($Results)) { if ($result.RebootRequired) { return $true } }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { return $true }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { return $true }
    $sm = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
        -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
    [bool]($sm -and $sm.PendingFileRenameOperations)
}

# Scan, install and repeat until no pending update is left.
#
# @example
#   Invoke-WindowsUpdates
function Invoke-WindowsUpdates {
    Write-Host "==> Checking Windows updates..."
    $state = @{
        checkedAt = (Get-Date).ToString('o'); skipped = $false; upToDate = $null
        pendingCount = $null; pendingSizeMb = $null
        rounds = 0; installed = 0; failed = 0; rebootRequired = $false
    }

    if ($SkipUpdateCheck) {
        $state.skipped = $true
        $script:UpdateCheckResult = $state
        Write-Host "==> Windows update stage skipped (-SkipUpdateCheck)."
        return
    }
    $state.upToDate = $false
    $state.pendingSizeMb = 0.0

    for ($round = 1; $round -le $Config.UpdateMaxRounds; $round++) {
        $state.rounds = $round
        $search = $null
        try { $search = Search-WindowsUpdates }
        catch { Write-Host "==> Windows Update scan failed: $($_.Exception.Message)"; break }

        try {
            $summaries = @($search.Updates | ForEach-Object { Get-UpdateSummary $_ })
            $state.pendingCount = $summaries.Count
            if ($summaries.Count -eq 0) {
                $state.upToDate = $true
                Write-Host "==> Windows is up to date; no pending updates."
                break
            }

            $state.pendingSizeMb = 0.0
            Write-Host "==> $($summaries.Count) update(s) pending:"
            foreach ($s in $summaries) {
                if ($null -ne $s.SizeMb) { $state.pendingSizeMb += $s.SizeMb }
                $kb = if ("$($s.KB)" -ne '') { " (KB $($s.KB))" } else { '' }
                $size = if ($null -ne $s.SizeMb) { " ({0:N1} MB)" -f $s.SizeMb } else { '' }
                Write-Host "==>   - $($s.Title)$kb$size"
            }
            Write-Host ("==> Total download size: {0:N1} MB." -f $state.pendingSizeMb)

            if (-not (Confirm-Step "Install these $($summaries.Count) update(s) now?")) {
                Write-Host '==> Update install declined; leaving the updates to Windows Update.'
                if (-not $Unattended) {
                    try { Start-Process $Config.UpdateSettings -ErrorAction Stop; Write-Host "==> Windows Update opened ($($Config.UpdateSettings))." }
                    catch { Write-Host "==> Could not open the Windows Update page: $($_.Exception.Message)" }
                }
                break
            }

            $results = @(Install-WindowsUpdates -Search $search -Summaries $summaries)
            $installed = @($results | Where-Object Succeeded).Count
            $state.installed += $installed
            $state.failed += $results.Count - $installed

            foreach ($r in $results) {
                $outcome = switch ($r.ResultCode) {
                    2 { 'installed' } 3 { 'installed with errors' }
                    4 { 'failed' } 5 { 'aborted' } default { "code $($r.ResultCode)" }
                }
                $kb = if ("$($r.KB)" -ne '') { " (KB $($r.KB))" } else { '' }
                Write-Host ("==>   - {0}{1}: {2} (0x{3:X8})" -f $r.Title, $kb, $outcome, $r.HResult)
            }
            if ($installed -eq 0) { Write-Host '==> No update was installed in this round; stopping the update loop.'; break }
            if (Test-RebootRequired -Results $results) {
                $state.rebootRequired = $true
                Write-Host '==> A reboot is required; reboot and run the bootstrap again for the remaining updates.'
                break
            }
        } finally {
            if ($search) {
                foreach ($u in @($search.Updates)) { Release-Com $u }
                foreach ($key in 'Updates', 'Result', 'Searcher', 'Session') { Release-Com $search[$key] }
            }
        }
    }

    $state.pendingSizeMb = [math]::Round($state.pendingSizeMb, 1)
    $script:UpdateCheckResult = $state
    Write-Host ("==> Windows Update: {0} round(s), {1} installed, {2} failed." -f $state.rounds, $state.installed, $state.failed)
}

# --- Windows Defender --------------------------------------------------------

# Read the Windows Security toggles the ReviOS playbook requires off.
#
# @return {string[]} Names of the toggles that are still on.
# @example
#   $on = @(Get-DefenderTogglesOn)
function Get-DefenderTogglesOn {
    $on = @()
    $status = Get-MpComputerStatus -ErrorAction SilentlyContinue
    $pref = Get-MpPreference -ErrorAction SilentlyContinue
    if ($status.RealTimeProtectionEnabled) { $on += 'Real-time protection' }
    if (-not $pref) { return $on }
    # MAPSReporting 0 = off; SubmitSamplesConsent 0 = never send.
    if ($pref.MAPSReporting) { $on += 'Cloud-delivered protection' }
    if ($pref.SubmitSamplesConsent) { $on += 'Automatic sample submission' }

    # Block at first sight is hidden, not a UI toggle, so it is ignored.
    $tamper = if ($null -ne $pref.DisableTamperProtection) { -not $pref.DisableTamperProtection }
    else {
        $features = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features' `
            -Name 'TamperProtection' -ErrorAction SilentlyContinue
        ($null -eq $features) -or ($features.TamperProtection -ne 0)
    }
    if ($tamper) { $on += 'Tamper protection' }
    $on
}

# Hand the toggles to the user, then check again. Nothing is written.
#
# @param {switch} Unattended - Report only and do not wait for the user.
# @return {bool} True when every toggle is off.
# @example
#   Invoke-DefenderCheck -Unattended:$Unattended
function Invoke-DefenderCheck {
    param([switch]$Unattended)
    Write-Host '==> Checking Windows Defender...'

    $on = @(Get-DefenderTogglesOn)
    if ($on.Count -eq 0) { Write-Host '==> Windows Defender is off; nothing to do.'; return $true }
    Write-Host "==> Still on: $($on -join ', ')"
    Write-Host '==> Turn them off in Windows Security > Virus & threat protection > Manage settings (Tamper protection first).'
    if ($Unattended) { Write-Host '==> Unattended run: the toggles stay as they are.'; return $false }

    foreach ($page in @('ms-settings:windowsdefender', 'windowsdefender://threatsettings')) {
        try { Start-Process $page -ErrorAction Stop; Write-Host "==> Windows Security opened ($page)."; break }
        catch { Write-Host "==> Could not open '$page': $($_.Exception.Message)" }
    }

    $null = Read-Host '==> Press Enter to check again'
    $on = @(Get-DefenderTogglesOn)
    if ($on.Count -eq 0) { Write-Host '==> Windows Defender is off.'; return $true }
    Write-Host "==> Still on: $($on -join ', ')"
    return $false
}

# --- Debloat -----------------------------------------------------------------

# Apply the ReviOS playbook headlessly via the TrustedUninstaller CLI.
#
# @example
#   Invoke-Debloat
function Invoke-Debloat {
    Write-Host "==> 1. Debloat (ReviOS)..."
    $marker = Join-Path $Config.StateDir 'stage-debloat.done'
    if (Test-Path $marker) { Write-Host "==> Debloat already applied; skipping."; return }

    # The playbook refuses to run against a protected machine.
    if (-not (Invoke-DefenderCheck -Unattended:$Unattended)) {
        throw "Debloat blocked: Windows Security toggles still on: $(@(Get-DefenderTogglesOn) -join ', '). Turn them off and re-run."
    }
    if (-not (Confirm-Step "Apply the ReviOS playbook now via the TrustedUninstaller CLI?")) {
        Write-Host "==> Debloat skipped by user; continuing without applying the playbook."
        return
    }
    Invoke-ReviCli -CliZipUrl $Config.CliStandalone -PlaybookUrl $Config.ReviPlaybook
    Set-Content -Path $marker -Value (Get-Date).ToString('o') -ErrorAction SilentlyContinue
    Write-Host "==> Debloat complete."
}

# --- Drivers -----------------------------------------------------------------

# List present devices that are not healthy.
#
# @return {object[]} Devices whose status is neither OK nor Unknown.
# @example
#   $problems = @(Get-UnhealthyDevices)
function Get-UnhealthyDevices {
    @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -notin 'OK', 'Unknown' })
}

# Install OEM/vendor drivers when a device is unhealthy, then verify.
#
# @example
#   Invoke-Drivers
function Invoke-Drivers {
    Write-Host "==> 2. Driver management (MSI laptop)..."
    $cs = Get-CimInstance Win32_ComputerSystem
    Write-Host "==> Detected: $($cs.Manufacturer) $($cs.Model)"

    $problems = @(Get-UnhealthyDevices)
    if ($problems.Count -eq 0) { Write-Host "==> All present devices healthy; skipping driver installation."; return }
    $problems | ForEach-Object { Write-Host "==> Device issue: $($_.FriendlyName) [$($_.Status)]" }

    $installer = Get-RemoteFile -Url $Config.MsiCenter -Directory $Config.Downloads
    if ($installer -like '*.zip') {
        $dir = Join-Path (Split-Path $installer) ([IO.Path]::GetFileNameWithoutExtension($installer))
        if (-not (Test-Path $dir)) { Expand-Archive -Path $installer -DestinationPath $dir -Force }
        $installer = (Get-ChildItem $dir -Recurse -Include *.exe, *.msi -ErrorAction SilentlyContinue |
            Select-Object -First 1).FullName
    }
    if ($installer -and (Test-Path $installer)) { Start-Process -FilePath $installer -Wait }

    if (Confirm-Step "Install the NVIDIA driver package?") {
        $nvidia = Get-RemoteFile -Url $Config.NvidiaDriver -Directory $Config.Downloads
        Start-Process -FilePath $nvidia -ArgumentList '-s' -Wait
    }

    Write-Host "==> Verifying devices..."
    $problems = @(Get-UnhealthyDevices)
    if ($problems.Count -eq 0) { Write-Host "==> All devices healthy."; Write-Host "==> Driver installation complete."; return }
    $problems | ForEach-Object { Write-Host "==> Device issue: $($_.FriendlyName) [$($_.Status)]" }
    if (-not (Confirm-Step "Continue despite device issues?")) {
        Write-Host "==> Device issues noted; continuing by user choice."
        return
    }
    Write-Host "==> Driver installation complete."
}

# --- Profile -----------------------------------------------------------------

# Check whether the profile is a symlink to the given source.
#
# @param {string} Path   - Profile path to inspect.
# @param {string} Source - Expected link target.
# @return {bool} True when the link is already correct.
# @example
#   Test-ProfileLinked -Path $PROFILE -Source $source
function Test-ProfileLinked {
    param([string]$Path, [string]$Source)
    $item = Get-Item $Path -ErrorAction SilentlyContinue
    $item.LinkType -eq 'SymbolicLink' -and $item.Target -contains $Source
}

# Link and verify the PowerShell profile, then save the completion state.
#
# @example
#   Complete-Bootstrap
function Complete-Bootstrap {
    Write-Host "==> 3. Link and verify..."
    # Use the live $PROFILE of this session, not a path captured at script start.
    $link = if ($ProfilePath) { $ProfilePath } else { $PROFILE.CurrentUserCurrentHost }
    $source = Join-Path $PSScriptRoot 'Microsoft.PowerShell_profile.ps1'

    if (Test-ProfileLinked -Path $link -Source $source) { Write-Host "==> Profile already linked; skipping." }
    else {
        New-Item -ItemType Directory -Path (Split-Path -Parent $link) -Force | Out-Null
        if (Test-Path $link) { Remove-Item $link -Force }
        New-Item -ItemType SymbolicLink -Path $link -Target $source | Out-Null
        Write-Host "==> Linked $link -> $source"
    }
    if (-not (Test-ProfileLinked -Path $link -Source $source)) { throw "Profile symlink verification failed." }

    $state = @{ status = 'complete'; finishedAt = (Get-Date).ToString('o'); profile = $link }
    if ($script:UpdateCheckResult) { $state.windowsUpdate = $script:UpdateCheckResult }
    Write-StateFile -State $state
    Write-Host "==> Completion state saved: $($Config.StateFile)"
    Write-Host "==> Bootstrap complete."
}

# --- Entry point -------------------------------------------------------------

# Run every stage in order and persist recovery state on failure.
#
# @example
#   main
function main {
    try {
        Write-Host "==> Bootstrapping..."
        # The state file is written even when an early stage fails.
        New-Item -ItemType Directory -Path $Config.StateDir -Force | Out-Null

        Assert-Administrator
        Invoke-WindowsUpdates
        Initialize-Environment
        Initialize-Scoop
        Initialize-Winget
        Invoke-Debloat
        Invoke-Drivers
        Complete-Bootstrap
    } catch {
        Write-Host "==> $($_.Exception.Message)"
        Write-StateFile -State @{ status = 'failed'; finishedAt = (Get-Date).ToString('o'); error = $_.Exception.Message }
        Write-Host "==> Recovery state saved: $($Config.StateFile)"
        Write-Host "Bootstrap failed or needs attention."
    } finally {
        if (-not $Unattended) { Write-Host 'Press Enter to close' -NoNewline; $null = Read-Host }
    }
}

# Dot-sourcing (tests, tooling) only defines the functions.
if ($MyInvocation.InvocationName -ne '.') {
    main
}
