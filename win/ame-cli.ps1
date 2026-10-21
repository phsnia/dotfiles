# ame-cli.ps1 — apply the ReviOS playbook headlessly via TrustedUninstaller CLI.
#
# Replaces the AME Wizard GUI (and its UI Automation) with the official CLI:
#   TrustedUninstaller.CLI.exe "<extracted playbook folder>" <option-ids...>
#
# A .apbx playbook is a 7z archive (password: malte) containing playbook.conf
# and the Configuration/ task tree. The option IDs passed to the CLI are the
# <Name> values of the wizard's feature pages, so CLI options reproduce the
# same selections the wizard would make.
#
# @example
#   . .\ame-cli.ps1
#   Invoke-ReviCli

# The shared helpers (Get-RemoteFile, Test-Artifact) live in lib/common.ps1.
# Load them when they are not defined yet, so this file also works alone.
if (-not (Get-Command Get-RemoteFile -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'lib\common.ps1')
}

# Default downloads location.
$script:CliDownloads = Join-Path $env:USERPROFILE 'Downloads'

# Option IDs matching the wizard flow: disable Defender, disable hibernate,
# tick every "remove" checkbox, and choose everything in the two "General
# configuration" pages (remove-pinned-items included).
# Notes:
#   - Edge is KEPT (no remove-edge) and browser-brave is omitted: Brave is
#     installed via winget in install-software.ps1 instead.
#   - remove-appx-xbox and disable-automatic-maintenance default to OFF in
#     the wizard - "choose all" turns them on.
$script:ReviOptions = @(
    'disable-defender'
    'disable-hibernate'
    'remove-onedrive'
    'remove-winsxs-ai'
    'remove-teams'
    'remove-appx-photos'
    'remove-appx-devhome'
    'remove-appx-xbox'
    'remove-appx-yourphone'
    'configure-wallpaper'
    'configure-darkmode'
    'configure-lcm'
    'configure-te'
    'remove-pinned-items-startmenu'
    'disable-automatic-maintenance'
)

# Locate 7-Zip (needed to unpack the .apbx; it is a 7z archive).
#
# @return {string} Full path to 7z.exe.
function Find-SevenZip {
    $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    foreach ($candidate in @(
            "$env:ProgramFiles\7-Zip\7z.exe",
            "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
            "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe",
            "$env:USERPROFILE\scoop\shims\7z.exe",
            "$env:ProgramData\scoop\shims\7z.exe"
        )) {
        if (Test-Path $candidate) { return $candidate }
    }

    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host '==> Installing 7zip via scoop...'
        scoop install 7zip
        $shim = "$env:USERPROFILE\scoop\shims\7z.exe"
        if (Test-Path $shim) { return $shim }
    }

    throw '7z.exe not found. Install 7-Zip (e.g. "scoop install 7zip") and re-run.'
}

# Extract a 7z archive with a password.
#
# @param {string} Archive     - Archive to extract.
# @param {string} Destination - Target directory.
# @param {string} Password    - Archive password.
function Expand-SevenZip {
    param(
        [Parameter(Mandatory)][string]$Archive,
        [Parameter(Mandatory)][string]$Destination,
        [string]$Password = 'malte'
    )

    & (Find-SevenZip) x $Archive "-o$Destination" "-p$Password" -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7z extraction failed (exit $LASTEXITCODE): $Archive" }
}

# Apply the ReviOS playbook through the TrustedUninstaller CLI.
#
# Downloads the CLI and the playbook, unpacks both, then runs:
#   TrustedUninstaller.CLI.exe "<playbook folder>" <option ids...>
# and waits for it to finish. Requires an elevated session.
#
# @param {string}   CliZipUrl  - CLI-Standalone.zip release asset.
# @param {string}   PlaybookUrl - .apbx playbook release asset.
# @param {string[]} Options    - Playbook option IDs.
# @param {string}   Destination - Download/work directory.
# @example
#   Invoke-ReviCli
function Invoke-ReviCli {
    param(
        [string]$CliZipUrl = 'https://github.com/Ameliorated-LLC/trusted-uninstaller-cli/releases/download/0.8.4/CLI-Standalone.zip',
        [string]$PlaybookUrl = 'https://github.com/meetrevision/playbook/releases/download/26.04/Revi-PB-26.04.apbx',
        [string[]]$Options = $script:ReviOptions,
        [string]$Destination = $script:CliDownloads
    )

    # Download + verify artifacts before touching the system.
    $cliZip = Get-RemoteFile -Url $CliZipUrl -Directory $Destination
    $playbook = Get-RemoteFile -Url $PlaybookUrl -Directory $Destination
    if (-not (Test-Artifact -Path $cliZip))    { throw "CLI archive is missing or empty: $cliZip" }
    if (-not (Test-Artifact -Path $playbook))  { throw "Playbook is missing or empty: $playbook" }

    # Unpack the CLI.
    $cliDir = Join-Path $Destination 'AME-CLI'
    if (-not (Get-ChildItem $cliDir -Recurse -Filter 'TrustedUninstaller.CLI.exe' -ErrorAction SilentlyContinue)) {
        Write-Host '==> Extracting TrustedUninstaller CLI...'
        New-Item -ItemType Directory -Path $cliDir -Force | Out-Null
        Expand-Archive -Path $cliZip -DestinationPath $cliDir -Force
    }

    $exe = (Get-ChildItem $cliDir -Recurse -Filter 'TrustedUninstaller.CLI.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1).FullName
    if (-not $exe) { throw "TrustedUninstaller.CLI.exe not found after extracting: $cliZip" }

    # Unpack the playbook (.apbx = 7z, password 'malte').
    $pbDir = Join-Path $cliDir 'playbook'
    if (-not (Get-ChildItem $pbDir -Recurse -Filter 'playbook.conf' -ErrorAction SilentlyContinue)) {
        Write-Host "==> Extracting playbook (7z, password 'malte')..."
        New-Item -ItemType Directory -Path $pbDir -Force | Out-Null
        Expand-SevenZip -Archive $playbook -Destination $pbDir -Password 'malte'
    }

    $conf = (Get-ChildItem $pbDir -Recurse -Filter 'playbook.conf' -ErrorAction SilentlyContinue |
        Select-Object -First 1)
    if (-not $conf) { throw "playbook.conf not found after extracting: $playbook" }
    $pbRoot = $conf.Directory.FullName

    # Apply. -NoNewWindow keeps the CLI's progress visible in this console.
    Write-Host "==> Applying ReviOS playbook via CLI with options: $($Options -join ' ')"
    $proc = Start-Process -FilePath $exe -ArgumentList (@("`"$pbRoot`"") + $Options) -Wait -NoNewWindow -PassThru
    if ($proc.ExitCode -ne 0) { throw "TrustedUninstaller CLI failed with exit code $($proc.ExitCode)." }
    Write-Host '==> TrustedUninstaller CLI finished.'
}
