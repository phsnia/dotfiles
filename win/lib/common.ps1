# common.ps1 — helpers shared by the Windows scripts.
#
# Dot-sourced by bootstrap.ps1, install-software.ps1 and ame-cli.ps1. Every
# function here is stateless: no configuration, no script scope, no side
# effects beyond the download it was asked for.

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
