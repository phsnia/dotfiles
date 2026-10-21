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
    # Windows Update downloads are independent, so the update stage fetches
    # them with this many parallel workers. Installation stays serial.
    UpdateDownloadConcurrency = 4
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
        Update-SessionPath

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

# Refresh $env:Path from the registry so programs installed during this
# run (scoop, App Installer) resolve without restarting the shell.
#
# @example
#   Update-SessionPath
function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
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
    # Verify: winget already resolves? Then skip.
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "==> winget already available; nothing to repair."
        return
    }

    Write-Host "==> winget (App Installer) missing; repairing..."

    # Route 1 - Microsoft Store update scan (best effort).
    try {
        if (Get-AppxPackage -Name Microsoft.WindowsStore -ErrorAction SilentlyContinue) {
            Write-Host "==> Requesting Microsoft Store update scan..."
            $scan = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' `
                -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01' -ErrorAction Stop
            $null = Invoke-CimMethod -InputObject $scan -MethodName 'UpdateScanMethod' -ErrorAction Stop

            # The Store applies updates asynchronously; poll for winget.
            foreach ($attempt in 1..6) {
                Start-Sleep -Seconds 5
                Update-SessionPath
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    Write-Host "==> winget available via the Microsoft Store."
                    return
                }
            }
            Write-Host "==> Microsoft Store did not provide App Installer; downloading instead."
        } else {
            Write-Host "==> Microsoft Store not present; downloading App Installer instead."
        }
    } catch {
        Write-Host "==> Microsoft Store repair failed: $($_.Exception.Message)"
    }

    # Route 2 - direct download of the winget-cli release (best effort).
    try {
        Write-Host "==> Downloading the latest winget-cli release..."
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' `
            -Headers @{ 'User-Agent' = 'dotfiles-bootstrap' } -ErrorAction Stop

        $bundleAsset = @($release.assets | Where-Object { $_.name -like '*.msixbundle' } | Select-Object -First 1)
        if ($bundleAsset.Count -eq 0) { throw "no .msixbundle asset in release '$($release.tag_name)'" }
        $bundle = Get-RemoteFile -Url $bundleAsset[0].browser_download_url -Directory $Config.Downloads

        # Dependency packages: recent releases ship them as a zip archive,
        # older ones as standalone .appx assets. The x64 dependencies match
        # the machine bootstrap runs on.
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
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "==> winget installed from the winget-cli release."
            return
        }
        Write-Host "==> winget still not on PATH after installing App Installer."
    } catch {
        Write-Host "==> App Installer download failed: $($_.Exception.Message)"
    }
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
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Repair-Winget
    }

    # Verify again: repair may have failed - winget is needed downstream.
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
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

# Download pending Windows updates concurrently.
#
# Downloads are independent of one another, so several WUA download jobs can
# run at the same time; Delivery Optimization splits each job across
# connections. Installation must stay serial (the CBS/TrustedInstaller
# servicing lock is exclusive), so this only fetches content into the
# SoftwareDistribution cache - Update-Windows still calls the normal install.
#
# One scan happens here, then each worker opens its own WUA session and
# downloads its slice. The update objects from that scan are passed to the
# workers; WUA update objects are read-only identity + metadata, so this is
# safe across runspaces.
#
# @param {int}    Concurrency - Maximum download workers. 1 disables overlap.
# @param {string} Criteria    - WUA search criteria for pending updates.
# @return {object[]} One result per update: UpdateID, Title, Ok, Message.
# @example
#   Invoke-ParallelUpdateDownload -Concurrency 4
function Invoke-ParallelUpdateDownload {
    param(
        [int]$Concurrency = 4,
        [string]$Criteria = "IsInstalled=0 and IsHidden=0 and Type='Software'"
    )

    # Worker: download the slice it was handed, one update at a time.
    $worker = {
        param([object[]]$Updates, [int]$Index, [int]$Total)

        $results = [System.Collections.Generic.List[object]]::new()
        $session = $null
        try {
            $session = New-Object -ComObject Microsoft.Update.Session
            foreach ($update in $Updates) {
                $id = "$($update.Identity.UpdateID)"
                $title = "$($update.Title)"
                try {
                    if ($update.IsDownloaded) {
                        $results.Add([pscustomobject]@{
                            UpdateID = $id; Title = $title; Ok = $true; Message = 'already downloaded'
                        })
                        continue
                    }

                    Write-Host "==> [download $Index/$Total] $title"
                    $collection = New-Object -ComObject Microsoft.Update.UpdateColl
                    $null = $collection.Add($update)
                    $downloader = $session.CreateUpdateDownloader()
                    $downloader.Updates = $collection
                    $code = [int]$downloader.Download().ResultCode
                    # 2 = Succeeded, 3 = SucceededWithErrors.
                    $ok = ($code -eq 2 -or $code -eq 3)
                    $results.Add([pscustomobject]@{
                        UpdateID = $id; Title = $title; Ok = $ok; Message = "result code $code"
                    })
                } catch {
                    $results.Add([pscustomobject]@{
                        UpdateID = $id; Title = $title; Ok = $false; Message = $_.Exception.Message
                    })
                }
            }
        } catch {
            foreach ($update in $Updates) {
                $results.Add([pscustomobject]@{
                    UpdateID = "$($update.Identity.UpdateID)"
                    Title    = "$($update.Title)"
                    Ok       = $false
                    Message  = $_.Exception.Message
                })
            }
        } finally {
            if ($session) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($session) }
        }

        return $results.ToArray()
    }

    # One scan is enough; workers reuse these update objects.
    $updates = @()
    $session = $null
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $found = $searcher.Search($Criteria)
        for ($i = 0; $i -lt $found.Updates.Count; $i++) {
            $updates += $found.Updates.Item($i)
        }
    } finally {
        if ($session) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($session) }
    }

    if ($updates.Count -eq 0) { return @() }

    $workers = [Math]::Max(1, [Math]::Min($Concurrency, $updates.Count))
    if ($workers -eq 1) {
        return @(& $worker -Updates $updates -Index 1 -Total 1)
    }

    # Round-robin slices keep worker payloads balanced by package, not size.
    $slices = @()
    for ($i = 0; $i -lt $workers; $i++) { $slices += ,@() }
    for ($i = 0; $i -lt $updates.Count; $i++) {
        $slices[$i % $workers] += $updates[$i]
    }

    Write-Host "==> Downloading $($updates.Count) update(s) with $workers parallel worker(s)..."

    $results = [System.Collections.Generic.List[object]]::new()
    $pool = [runspacefactory]::CreateRunspacePool(1, $workers)
    $pool.Open()
    $handles = @()
    try {
        for ($i = 0; $i -lt $workers; $i++) {
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($worker.ToString()).
                AddArgument([object[]]$slices[$i]).
                AddArgument($i + 1).
                AddArgument($workers)
            $handles += [pscustomobject]@{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Slice = $slices[$i] }
        }

        foreach ($entry in $handles) {
            # Worker output is not reliably visible in the host, so report
            # progress from the main thread while the jobs run.
            $lastReport = Get-Date
            while (-not $entry.Handle.IsCompleted) {
                if (((Get-Date) - $lastReport).TotalSeconds -ge 15) {
                    $done = 0
                    foreach ($update in $updates) {
                        try { if ($update.IsDownloaded) { $done++ } } catch { }
                    }
                    Write-Host "==> Download progress: $done/$($updates.Count) update(s) downloaded."
                    $lastReport = Get-Date
                }
                Start-Sleep -Milliseconds 500
            }

            try {
                foreach ($item in @($entry.PowerShell.EndInvoke($entry.Handle))) {
                    $results.Add($item)
                }
            } catch {
                foreach ($update in $entry.Slice) {
                    $results.Add([pscustomobject]@{
                        UpdateID = "$($update.Identity.UpdateID)"
                        Title    = "$($update.Title)"
                        Ok       = $false
                        Message  = $_.Exception.Message
                    })
                }
            } finally {
                $entry.PowerShell.Dispose()
            }
        }
    } finally {
        $pool.Close()
        $pool.Dispose()
    }

    return $results.ToArray()
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

        # Scan only - do not install yet. Get-WindowsUpdate can hand back a
        # nested array; re-emitting each element flattens it to one update each.
        $updates = @(Get-WindowsUpdate -ErrorAction Stop | ForEach-Object { $_ })

        if ($updates.Count -eq 0) {
            Write-Host "==> Windows is already up to date; skipping update (no reboot needed)."
            return
        }

        Write-Host "==> $($updates.Count) update(s) pending:"
        $unitMb = @{ B = 1.0 / 1MB; KB = 1KB / 1MB; MB = 1.0; GB = 1024.0 }
        foreach ($update in $updates) {
            # PSWindowsUpdate reports Size as a unit-suffixed string ("44MB",
            # "1GB"); older builds returned a byte count, sometimes as an array.
            $parts = @($update.Size) | Where-Object { $_ -ne $null -and "$_" -ne '' }
            $sizeMb = $null
            $parsed = $parts.Count -gt 0
            $sum = 0.0
            foreach ($part in $parts) {
                if ("$part" -match '^\s*([\d.,]+)\s*(B|KB|MB|GB)\s*$') {
                    $number = [double]($matches[1] -replace ',', '.')
                    $sum += $number * $unitMb[$matches[2].ToUpper()]
                } else {
                    $number = 0.0
                    if ([double]::TryParse("$part", [ref]$number)) { $sum += $number / 1MB }
                    else { $parsed = $false }
                }
            }
            if ($parsed) { $sizeMb = $sum }

            if ($null -ne $sizeMb) {
                Write-Host ("==>   - {0} ({1:N1} MB)" -f $update.Title, $sizeMb)
            } elseif ($parts.Count -gt 0) {
                Write-Host ("==>   - {0} ({1})" -f $update.Title, ($parts -join ', '))
            } else {
                Write-Host ("==>   - {0}" -f $update.Title)
            }
        }

        # Installing means a reboot later - let the user decide.
        if (-not (Confirm-Step "Install these updates now? (a reboot will be needed)")) {
            Write-Host "==> Windows update skipped by user; continuing without installing updates."
            return
        }

        # Fetch content in parallel first. This is best effort: if the parallel
        # pass fails, the serial install below downloads whatever is missing.
        if ($Config.UpdateDownloadConcurrency -gt 1 -and $updates.Count -gt 1) {
            try {
                $downloads = @(Invoke-ParallelUpdateDownload -Concurrency $Config.UpdateDownloadConcurrency)
                $failed = @($downloads | Where-Object { -not $_.Ok })
                if ($failed.Count -gt 0) {
                    Write-Host "==> $($failed.Count) download(s) failed; the install pass will retry."
                } else {
                    Write-Host "==> Downloads complete."
                }
            } catch {
                Write-Host "==> Parallel download skipped: $($_.Exception.Message)"
            }
        }

        # Installs stay serial: CBS/TrustedInstaller allows one at a time.
        Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot
        Write-Host "==> Windows update finished. Reboot required to finish installing updates."
    } catch {
        Write-Host "==> Windows update skipped: $($_.Exception.Message)"
    }
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

    # Tamper Protection has no preference switch; read its registry state.
    $features = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features' `
        -Name 'TamperProtection' -ErrorAction SilentlyContinue
    if ($features -and $features.TamperProtection -ne 0) { $on.Add('Tamper protection') }

    return $on.ToArray()
}

# Write the Defender policy flag the ReviOS playbook checks for.
#
# @example
#   Set-DefenderPolicy
function Set-DefenderPolicy {
    $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
    if (-not (Test-Path $policy)) { New-Item -Path $policy -Force | Out-Null }
    Set-ItemProperty -Path $policy -Name 'DisableAntiSpyware' -Value 1 -Type DWord -ErrorAction SilentlyContinue
}

# Turn off Windows Defender protections before the playbook runs.
# Verify: all four Windows Security toggles already off? Then skip.
# Tamper Protection blocks every preference write and can only be turned
# off by hand, so it is requested first (up to three tries).
#
# @example
#   Disable-Defender
function Disable-Defender {
    # Verify: already disabled? Then skip.
    $on = @(Get-DefenderTogglesOn)
    if ($on.Count -eq 0) {
        Write-Host "==> Defender toggles already off; skipping."
        return
    }

    Write-Host "==> Turning off Windows Defender..."
    Write-Host "==> Still on: $($on -join ', ')"

    if ($on -contains 'Tamper protection') {
        foreach ($attempt in 1..3) {
            Write-Host "==> Turn off Tamper Protection: Windows Security > Virus & threat protection > Manage settings."
            if (-not (Confirm-Step "Tamper Protection turned off?")) { break }
            if (@(Get-DefenderTogglesOn) -notcontains 'Tamper protection') { break }
            Write-Host "==> Tamper Protection is still on."
        }
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
        Write-Host "==> Defender protections disabled."
    } catch {
        Write-Host "==> Could not disable Defender protections: $($_.Exception.Message)"
    }

    # Policy keys the ReviOS playbook checks for.
    Set-DefenderPolicy

    $on = @(Get-DefenderTogglesOn)
    if ($on.Count -gt 0) {
        Write-Host "==> Still on: $($on -join ', ')"
    } else {
        Write-Host "==> All Windows Security toggles are off."
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

        # The CLI loops on "press any key" while any of the four Windows
        # Security toggles is still on; fail clearly instead of hanging.
        $togglesOn = @(Get-DefenderTogglesOn)
        if ($togglesOn.Count -gt 0) {
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
