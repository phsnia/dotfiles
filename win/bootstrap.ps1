# bootstrap.ps1 — Windows dotfiles bootstrap
#
# Implements win/ARCHITECTURE.md: elevate, initialize scoop (git only) and
# winget, install the pending Windows updates, debloat, manage drivers, link
# the profile and verify.
# Software installation lives in install-software.ps1.
#
# The file is read top-down in numbered sections:
#
#   1. Configuration    - paths, URLs and the shared switches.
#   2. Support          - the helpers the stages build on.
#   3. Environment      - execution policy and directories.
#   4. Scoop            - scoop plus git, the only package installed here.
#   5. Winget           - App Installer, installed when it is missing.
#   6. Windows Update   - scan, install and repeat until no package is left.
#   7. Windows Defender - the four toggles the ReviOS playbook needs off.
#   8. Debloat          - the ReviOS playbook.
#   9. Drivers          - OEM and vendor driver packages.
#  10. Profile          - symlink $PROFILE into this repo.
#  11. Entry point      - main.
#
# The stages do not run in that order: the Windows Update stage runs first
# (right after the elevation), so the machine is patched before scoop,
# winget, the debloat and the drivers touch it.
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

# Result of the Windows update stage, saved to the state file.
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
    UpdateMaxRounds = 5
}

# -----------------------------------------------------------------------------
# 2. Support
# -----------------------------------------------------------------------------

# Ask the user to confirm an interactive step.
function Confirm-Step {
    param([Parameter(Mandatory)][string]$Question)

    if ($Unattended) {
        Write-Host "==> (unattended) auto-confirming: $Question"
        return $true
    }
    return ((Read-Host "$Question (y/N)") -eq 'y')
}

# Write the state file that records how the bootstrap ended.
function Write-StateFile {
    param([Parameter(Mandatory)][hashtable]$State)

    $State | ConvertTo-Json | Set-Content -Path $Config.StateFile -ErrorAction SilentlyContinue
}

# Refresh $env:Path from the registry so programs installed during this run
# (scoop, App Installer) resolve without restarting the shell.
function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

# Release a COM object so its handle does not stay open for the rest of the run.
function Release-Com {
    param([Parameter(Mandatory)][AllowNull()]$Object)

    if ($null -eq $Object) { return }

    try {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Object)
    } catch {
        # Not a COM object (or already released) - nothing to release.
    }
}

# -----------------------------------------------------------------------------
# 3. Environment
# -----------------------------------------------------------------------------

# Ensure the script is elevated, relaunching the same host via RunAs if not.
function Assert-Administrator {
    $admin = (
        [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($admin) { return }

    # Relaunch this host, not powershell.exe, so $PROFILE stays pwsh's.
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($ProfilePath) { $argList += " -ProfilePath `"$ProfilePath`"" }
    if ($Unattended) { $argList += ' -Unattended' }
    if ($SkipUpdateCheck) { $argList += ' -SkipUpdateCheck' }

    Write-Host "==> Not elevated; relaunching as administrator..."
    Start-Process (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList
    exit
}

# Prepare the execution environment: the execution policy and the directories.
function Initialize-Environment {
    Write-Host "==> Initializing environment..."

    # Group Policy may block the CurrentUser scope; the script itself runs
    # under -ExecutionPolicy Bypass, so this only affects future shells.
    $policy = (Get-ExecutionPolicy -List -ErrorAction SilentlyContinue |
        Where-Object Scope -eq 'CurrentUser').ExecutionPolicy

    if ($policy -eq 'RemoteSigned') {
        Write-Host "==> Execution policy already RemoteSigned; skipping."
    } else {
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
            Write-Host "==> Execution policy set to RemoteSigned (CurrentUser)."
        } catch {
            Write-Host "==> Execution policy not set: $($_.Exception.Message)"
        }
    }

    # The directories are the end state of this stage: already there → skip.
    $missing = @(@($Config.Downloads, $Config.StateDir) | Where-Object { -not (Test-Path $_) })
    if ($missing.Count -eq 0) {
        Write-Host "==> Directories already exist; skipping."
        return
    }

    try {
        New-Item -ItemType Directory -Path $missing -Force | Out-Null
        Write-Host "==> Directory created: $($missing -join ', ')"
    } catch {
        Write-Host "==> Directory creation failed: $($_.Exception.Message)"
    }
}

# -----------------------------------------------------------------------------
# 4. Scoop
# -----------------------------------------------------------------------------

# Install Scoop if missing (or update it), add the bundled main bucket and
# install git - the only package bootstrap installs.
function Initialize-Scoop {
    Write-Host "==> Initializing scoop..."

    try {
        # Install Scoop when it is missing, or update it when it is there.
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
        Update-SessionPath

        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
            throw "scoop not found on PATH after installation."
        }

        # The main bucket ships with Scoop; add it when it is missing.
        if (scoop bucket list 2>$null | Select-String -SimpleMatch 'main') {
            Write-Host "==> Scoop bucket 'main' already added; skipping."
        } else {
            scoop bucket add main
        }

        # Git is the only package bootstrap installs.
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

# -----------------------------------------------------------------------------
# 5. Winget
# -----------------------------------------------------------------------------

# Check whether winget resolves on PATH.
function Test-WingetAvailable {
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

# Install the latest winget-cli release from GitHub when winget is missing.
function Install-WingetFromRelease {
    try {
        Write-Host "==> Downloading the latest winget-cli release..."
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' `
            -Headers @{ 'User-Agent' = 'dotfiles-bootstrap' } -ErrorAction Stop

        $bundleAsset = @($release.assets | Where-Object { $_.name -like '*.msixbundle' } | Select-Object -First 1)
        if ($bundleAsset.Count -eq 0) { throw "no .msixbundle asset in release '$($release.tag_name)'" }
        $bundle = Get-RemoteFile -Url $bundleAsset[0].browser_download_url -Directory $Config.Downloads

        # The .appx dependencies: recent releases ship them as a zip archive,
        # older ones as standalone .appx assets. The x64 ones match the
        # machine bootstrap runs on.
        $deps = @()
        $depZip = @($release.assets | Where-Object { $_.name -like '*Dependencies*.zip' } | Select-Object -First 1)
        if ($depZip.Count -gt 0) {
            $zip = Get-RemoteFile -Url $depZip[0].browser_download_url -Directory $Config.Downloads
            $extract = Join-Path (Split-Path $zip) ([IO.Path]::GetFileNameWithoutExtension($zip))
            if (-not (Test-Path $extract)) { Expand-Archive -Path $zip -DestinationPath $extract -Force }
            $deps = @(Get-ChildItem $extract -Recurse -Include *.appx -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match 'x64' } | ForEach-Object { $_.FullName })
        }

        if ($deps.Count -eq 0) {
            $deps = @($release.assets | Where-Object { $_.name -like '*.appx' } |
                ForEach-Object { Get-RemoteFile -Url $_.browser_download_url -Directory $Config.Downloads })
        }

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

# Verify winget (App Installer) is available and refresh its sources.
function Initialize-Winget {
    Write-Host "==> Initializing winget..."

    # A missing winget is repaired from the latest winget-cli release.
    if (-not (Test-WingetAvailable)) {
        Write-Host "==> winget (App Installer) missing; repairing..."
        Install-WingetFromRelease
    }

    # The repair may have failed - winget is needed downstream.
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
# 6. Windows Update (scan, install, repeat)
# -----------------------------------------------------------------------------

# Scan for pending Windows updates through the built-in Windows Update client
# API and keep the live update objects, so one scan feeds report and install.
function Search-WindowsUpdates {
    $session = $null
    $searcher = $null
    $result = $null

    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()

        # ssWindowsUpdate (2) plus the Microsoft Update service id: scan the
        # public catalogue even when the machine has a managed server.
        try {
            $searcher.ServerSelection = 2
            $searcher.ServiceID = '7971F918-A847-4430-9279-4A52D1EFE18D'
        } catch {
            Write-Host '==> Microsoft Update target refused; using the configured update source.'
        }

        # IsInstalled=0 - not on the machine yet; IsHidden=0 - the ones the
        # user should see.
        $result = $searcher.Search('IsInstalled=0 and IsHidden=0')
    } catch {
        Release-Com $searcher
        Release-Com $session
        throw "Windows Update scan failed: $($_.Exception.Message)"
    }

    return @{
        Session  = $session
        Searcher = $searcher
        Result   = $result
        Updates  = $result.Updates
    }
}

# Summarize one pending update for the report: title, KB and download size.
function Get-UpdateSummary {
    param([Parameter(Mandatory)]$Update)

    $summary = [pscustomobject]@{ UpdateID = ''; Title = ''; SizeMb = $null; KB = '' }

    try {
        $summary.UpdateID = "$($Update.UpdateID)"
        $summary.Title = "$($Update.Title)"
        $summary.KB = @($Update.KBArticleIDs) -join ', '

        # MaxDownloadSize is a 32-bit ULONG. Reading it through the COM binder
        # can carry junk in the upper bits, so the value is masked back to 32
        # bits. A size of zero means the client does not know it.
        $raw = [int64]$Update.MaxDownloadSize
        if ($raw -gt 4294967295) { $raw = $raw % 4294967296 }   # low 32 bits
        if ($raw -gt 0) { $summary.SizeMb = $raw / 1MB }
    } catch {
        # A property the client does not expose: the summary stays partial.
    }

    return $summary
}

# Download and install the pending updates of a scan. The downloader and the
# installer are two steps: the installer only applies what is on disk, and
# downloading needs elevation. Installs stay serial - CBS/TrustedInstaller
# holds an exclusive servicing lock (0x80240016 / 1618 otherwise).
function Install-WindowsUpdates {
    param(
        [Parameter(Mandatory)][hashtable]$Search,
        [object[]]$Summaries = @()
    )

    $session = $Search.Session
    $updates = $Search.Updates

    # An update whose license was never accepted is refused by the installer.
    foreach ($update in @($updates)) {
        try {
            if (-not $update.EulaAccepted) { $update.AcceptEula() }
        } catch {
            Write-Host "==> Could not accept the license of an update: $($_.Exception.Message)"
        }
    }

    # The downloader fetches the payload, the installer applies it.
    $downloader = $null
    try {
        Write-Host '==> Downloading the pending updates...'
        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $updates
        $null = $downloader.Download()
    } catch {
        Write-Host "==> Download failed: $($_.Exception.Message)"
    } finally {
        Release-Com $downloader
    }

    # The summaries, keyed by update id, so every result is reported with the
    # title and the KB of its update.
    $names = @{}
    foreach ($summary in @($Summaries)) {
        if ($summary.UpdateID) { $names[$summary.UpdateID] = $summary }
    }

    $installer = $null
    $installResult = $null
    try {
        Write-Host '==> Installing the updates (this can take several minutes)...'
        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $updates
        $installResult = $installer.Install()
    } catch {
        Write-Host "==> Install failed: $($_.Exception.Message)"
        return @()
    } finally {
        Release-Com $installer
    }

    $results = @()
    foreach ($result in @($installResult)) {
        $updateId = "$($result.UpdateID)"
        $summary = $names[$updateId]
        $code = [int]$result.ResultCode

        $results += [pscustomobject]@{
            Title          = $(if ($summary) { $summary.Title } else { $updateId })
            KB             = $(if ($summary) { $summary.KB } else { '' })
            ResultCode     = $code
            HResult        = [int]$result.HResult
            RebootRequired = [bool]$result.RebootRequired
            # 2 = succeeded, 3 = succeeded with errors.
            Succeeded      = ($code -eq 2 -or $code -eq 3)
        }

        Release-Com $result
    }

    Release-Com $installResult

    return $results
}

# Check whether Windows wants a reboot before the next update can land: the
# flag of the installer result plus the three registry signals.
function Test-RebootRequired {
    param([object[]]$Results = @())

    foreach ($result in @($Results)) {
        if ($result.RebootRequired) { return $true }
    }

    # A component based servicing operation is waiting for a reboot.
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        return $true
    }

    # The Windows Update client flagged a pending reboot.
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        return $true
    }

    # A file rename is pending: the swap happens at the next boot.
    $sessionManager = Get-ItemProperty `
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
        -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
    return [bool]($sessionManager -and $sessionManager.PendingFileRenameOperations)
}

# Scan, install and repeat until Windows has no pending update package left.
# Every round starts with a full scan: the pending list is printed before
# anything is installed, and the install runs on exactly that set. The loop
# stops for three reasons only: no package left (done), a reboot is pending
# (the rest is picked up after the reboot) or a round installed nothing
# (no progress - the round cap ends the loop too).
function Invoke-WindowsUpdates {
    Write-Host "==> Checking Windows updates..."

    # The state block is filled while the stage runs and handed to the
    # completion stage through the script scope.
    $state = @{
        checkedAt      = (Get-Date).ToString('o')
        skipped        = $false
        upToDate       = $null
        pendingCount   = $null
        pendingSizeMb  = $null
        rounds         = 0
        installed      = 0
        failed         = 0
        rebootRequired = $false
    }

    if ($SkipUpdateCheck) {
        Write-Host "==> Windows update stage skipped (-SkipUpdateCheck)."
        $state.skipped = $true
        $script:UpdateCheckResult = $state
        return
    }

    $state.upToDate = $false
    $state.pendingSizeMb = 0.0

    for ($round = 1; $round -le $Config.UpdateMaxRounds; $round++) {
        $state.rounds = $round

        $search = $null
        try {
            $search = Search-WindowsUpdates
        } catch {
            Write-Host "==> Windows Update scan failed: $($_.Exception.Message)"
            break
        }

        try {
            $summaries = @($search.Updates | ForEach-Object { Get-UpdateSummary -Update $_ })
            $state.pendingCount = $summaries.Count

            # No package left: the stage is done.
            if ($state.pendingCount -eq 0) {
                Write-Host "==> Windows is up to date; no pending updates."
                $state.upToDate = $true
                break
            }

            # Report the pending packages and the size they need.
            $state.pendingSizeMb = 0.0
            Write-Host "==> $($state.pendingCount) update(s) pending:"
            foreach ($summary in $summaries) {
                $size = ''
                if ($null -ne $summary.SizeMb) {
                    $state.pendingSizeMb += $summary.SizeMb
                    $size = " ({0:N1} MB)" -f $summary.SizeMb
                }

                $kb = ''
                if ("$($summary.KB)" -ne '') { $kb = " (KB $($summary.KB))" }

                Write-Host ("==>   - {0}{1}{2}" -f $summary.Title, $kb, $size)
            }
            Write-Host ("==> Total download size: {0:N1} MB." -f $state.pendingSizeMb)

            if (-not (Confirm-Step "Install these $($state.pendingCount) update(s) now?")) {
                Write-Host '==> Update install declined; leaving the updates to Windows Update.'
                if (-not $Unattended) {
                    try {
                        Start-Process $Config.UpdateSettings -ErrorAction Stop
                        Write-Host "==> Windows Update opened ($($Config.UpdateSettings)); install the updates there."
                    } catch {
                        Write-Host "==> Could not open the Windows Update page: $($_.Exception.Message)"
                    }
                }
                break
            }

            $roundResults = @(Install-WindowsUpdates -Search $search -Summaries $summaries)
            $roundInstalled = @($roundResults | Where-Object { $_.Succeeded }).Count
            $state.installed += $roundInstalled
            $state.failed += @($roundResults | Where-Object { -not $_.Succeeded }).Count

            foreach ($result in $roundResults) {
                $outcome = switch ($result.ResultCode) {
                    2 { 'installed' }
                    3 { 'installed with errors' }
                    4 { 'failed' }
                    5 { 'aborted' }
                    default { "code $($result.ResultCode)" }
                }
                $kb = ''
                if ("$($result.KB)" -ne '') { $kb = " (KB $($result.KB))" }
                Write-Host ("==>   - {0}{1}: {2} (0x{3:X8})" -f $result.Title, $kb, $outcome, $result.HResult)
            }

            # Nothing was installed: the loop would spin on the same packages.
            if ($roundInstalled -eq 0) {
                Write-Host '==> No update was installed in this round; stopping the update loop.'
                break
            }

            # A pending reboot keeps the same packages in the next scan: the
            # remaining updates are picked up after the reboot.
            if (Test-RebootRequired -Results $roundResults) {
                $state.rebootRequired = $true
                Write-Host '==> A reboot is required; reboot and run the bootstrap again for the remaining updates.'
                break
            }
        } finally {
            # Release the COM objects of the scan: the updates one by one,
            # then the collection and the session around it.
            if ($search) {
                foreach ($update in @($search.Updates)) { Release-Com $update }
                Release-Com $search.Updates
                Release-Com $search.Result
                Release-Com $search.Searcher
                Release-Com $search.Session
            }
        }
    }

    $state.pendingSizeMb = [math]::Round($state.pendingSizeMb, 1)
    $script:UpdateCheckResult = $state

    Write-Host ("==> Windows Update: {0} round(s), {1} installed, {2} failed." -f $state.rounds, $state.installed, $state.failed)
}

# -----------------------------------------------------------------------------
# 7. Windows Defender
# -----------------------------------------------------------------------------

# Read the Windows Security toggles the ReviOS playbook requires off. The
# wizard checks the four toggles on Virus & threat protection > Manage
# settings: real-time, cloud-delivered, sample submission, Tamper Protection.
function Get-DefenderTogglesOn {
    $on = [System.Collections.Generic.List[string]]::new()

    $status = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($status -and $status.RealTimeProtectionEnabled) { $on.Add('Real-time protection') }

    $pref = Get-MpPreference -ErrorAction SilentlyContinue
    if (-not $pref) { return $on.ToArray() }   # Defender is not installed

    # Cloud-delivered protection: the "Microsoft Defender Antivirus cloud
    # protection" toggle maps to MAPSReporting (0 = off, 1 = basic, 2 = advanced).
    # "Block at first sight" (DisableBlockAtFirstSeen) is a hidden preference the
    # UI does not expose: it keeps its default, so reading it reported the
    # toggle as on forever.
    if ($null -ne $pref.MAPSReporting -and $pref.MAPSReporting -ne 0) { $on.Add('Cloud-delivered protection') }

    # Automatic sample submission: the toggle maps to SubmitSamplesConsent
    # (0 = never send, 1 = safe samples, 2 = always send). Only a value above 0
    # means the toggle is on.
    if ($null -ne $pref.SubmitSamplesConsent -and $pref.SubmitSamplesConsent -ne 0) { $on.Add('Automatic sample submission') }

    # Tamper Protection: the module preference is authoritative, the
    # registry value is the fallback for builds without the preference.
    # A toggle that cannot be read counts as on - the playbook would
    # refuse to run against a protected machine.
    if ($null -ne $pref.DisableTamperProtection) {
        $tamper = -not $pref.DisableTamperProtection
    } else {
        $features = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features' `
            -Name 'TamperProtection' -ErrorAction SilentlyContinue
        $tamper = ($null -eq $features) -or ($features.TamperProtection -ne 0)
    }
    if ($tamper) { $on.Add('Tamper protection') }

    return $on.ToArray()
}

# Check the toggles, hand them to the user when one is still on, then check
# again. Nothing is written: Tamper protection refuses every scripted
# change, so the platform is only ever changed by hand.
function Invoke-DefenderCheck {
    param([switch]$Unattended)

    Write-Host '==> Checking Windows Defender...'

    $on = @(Get-DefenderTogglesOn)
    if ($on.Count -eq 0) {
        Write-Host '==> Windows Defender is off; nothing to do.'
        return $true
    }

    Write-Host "==> Still on: $($on -join ', ')"
    Write-Host '==> Turn them off in Windows Security > Virus & threat protection > Manage settings (Tamper protection first).'

    # An unattended run has nobody to switch the toggles: report and stop.
    if ($Unattended) {
        Write-Host '==> Unattended run: the toggles stay as they are.'
        return $false
    }

    # Open the page that holds the toggles so the user can switch them off.
    foreach ($page in @('ms-settings:windowsdefender', 'windowsdefender://threatsettings')) {
        try {
            Start-Process $page -ErrorAction Stop
            Write-Host "==> Windows Security opened ($page)."
            break
        } catch {
            Write-Host "==> Could not open '$page': $($_.Exception.Message)"
        }
    }

    $null = Read-Host '==> Press Enter to check again'

    $on = @(Get-DefenderTogglesOn)
    if ($on.Count -eq 0) {
        Write-Host '==> Windows Defender is off.'
        return $true
    }

    Write-Host "==> Still on: $($on -join ', ')"
    return $false
}

# -----------------------------------------------------------------------------
# 8. Debloat
# -----------------------------------------------------------------------------

# Apply the ReviOS playbook headlessly with the TrustedUninstaller CLI, once.
function Invoke-Debloat {
    Write-Host "==> 1. Debloat (ReviOS)..."

    # The marker keeps a second run from applying the playbook again.
    $marker = Join-Path $Config.StateDir 'stage-debloat.done'
    if (Test-Path $marker) {
        Write-Host "==> Debloat already applied (stage marker found); skipping."
        return
    }

    try {
        # Defender must be off before the playbook is applied: the playbook
        # refuses to run against a protected machine. Nothing is scripted -
        # the check opens Windows Security and waits for the four toggles.
        if (-not (Invoke-DefenderCheck -Unattended:$Unattended)) {
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
        # Brave installed later via install-software.ps1). The CLI downloads
        # and verifies the playbook itself.
        Invoke-ReviCli -CliZipUrl $Config.CliStandalone -PlaybookUrl $Config.ReviPlaybook
    } catch {
        Write-Host "==> Debloat failed: $($_.Exception.Message)"
        throw
    }

    Set-Content -Path $marker -Value (Get-Date).ToString('o') -ErrorAction SilentlyContinue
    Write-Host "==> Stage marked done: debloat"
    Write-Host "==> Debloat complete."
}

# -----------------------------------------------------------------------------
# 9. Drivers
# -----------------------------------------------------------------------------

# List the present devices that are not healthy.
function Get-UnhealthyDevices {
    return @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' })
}

# Detect the hardware, install OEM/vendor drivers and verify the devices.
function Invoke-Drivers {
    Write-Host "==> 2. Driver management (MSI laptop)..."

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        Write-Host "==> Detected: $($cs.Manufacturer) $($cs.Model)"

        # All present devices healthy: nothing to install.
        $problems = @(Get-UnhealthyDevices)
        if ($problems.Count -eq 0) {
            Write-Host "==> All present devices healthy; skipping driver installation."
            return
        }

        foreach ($device in $problems) {
            Write-Host "==> Device issue: $($device.FriendlyName) [$($device.Status)]"
        }

        # Install the MSI OEM driver bundle.
        $msi = Get-RemoteFile -Url $Config.MsiCenter -Directory $Config.Downloads
        $installer = $msi
        if ($msi -like '*.zip') {
            $extract = Join-Path (Split-Path $msi) ([IO.Path]::GetFileNameWithoutExtension($msi))
            if (-not (Test-Path $extract)) { Expand-Archive -Path $msi -DestinationPath $extract -Force }
            $installer = (Get-ChildItem $extract -Recurse -Include *.exe, *.msi -ErrorAction SilentlyContinue |
                Select-Object -First 1).FullName
        }
        if ($installer -and (Test-Path $installer)) {
            Start-Process -FilePath $installer -Wait
        }

        # Install a vendor GPU driver if needed.
        if (Confirm-Step "Install the NVIDIA driver package?") {
            $nvidia = Get-RemoteFile -Url $Config.NvidiaDriver -Directory $Config.Downloads
            Start-Process -FilePath $nvidia -ArgumentList '-s' -Wait
        }
    } catch {
        Write-Host "==> Driver installation failed: $($_.Exception.Message)"
        throw
    }

    # Verify the devices again after the install.
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

# Link the PowerShell profile, verify it and save the completion state.
function Complete-Bootstrap {
    Write-Host "==> 3. Link and verify..."

    # Link against the live $PROFILE of this session (or the explicit
    # -ProfilePath override), not a path captured at script start.
    $linkPath = if ($ProfilePath) { $ProfilePath } else { $PROFILE.CurrentUserCurrentHost }
    $source = Join-Path $PSScriptRoot 'Microsoft.PowerShell_profile.ps1'

    try {
        if (Test-ProfileLinked -Path $linkPath -Source $source) {
            Write-Host "==> Profile already linked; skipping."
        } else {
            # Replace the profile with a symlink to the source.
            New-Item -ItemType Directory -Path (Split-Path -Parent $linkPath) -Force | Out-Null
            if (Test-Path $linkPath) { Remove-Item $linkPath -Force }
            New-Item -ItemType SymbolicLink -Path $linkPath -Target $source | Out-Null
            Write-Host "==> Linked $linkPath -> $source"
        }

        # Verify the link.
        if (-not (Test-ProfileLinked -Path $linkPath -Source $source)) {
            throw "Profile symlink verification failed."
        }
    } catch {
        Write-Host "==> Profile link failed: $($_.Exception.Message)"
        throw
    }

    # Persist the completion state.
    $state = @{
        status     = 'complete'
        finishedAt = (Get-Date).ToString('o')
        profile    = $linkPath
    }

    # The Windows update check result, when the check ran.
    if ($script:UpdateCheckResult) { $state['windowsUpdate'] = $script:UpdateCheckResult }

    Write-StateFile -State $state
    Write-Host "==> Completion state saved: $($Config.StateFile)"
    Write-Host "==> Bootstrap complete."
}

# -----------------------------------------------------------------------------
# 11. Entry point
# -----------------------------------------------------------------------------

# Entry point: run each stage in order and handle failures.
function main {
    try {
        Write-Host "==> Bootstrapping..."

        New-Item -ItemType Directory -Path $Config.StateDir -Force | Out-Null

        Write-Host "==> Bootstrap started."

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

        # Persist the recovery state so the next run knows what happened.
        Write-StateFile -State @{
            status     = 'failed'
            finishedAt = (Get-Date).ToString('o')
            error      = $_.Exception.Message
        }
        Write-Host "==> Recovery state saved: $($Config.StateFile)"
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
