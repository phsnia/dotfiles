# Revi OS
$D = "$env:USERPROFILE\Downloads"
function Download-IfMissing {
    param (
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Directory
    )

    $FileName = Split-Path $Url -Leaf
    $Output = Join-Path $Directory $FileName

    if (Test-Path $Output) {
        Write-Host "Already exists: $FileName"
        return
    }

    Write-Host "Downloading: $FileName"

    curl.exe -L $Url -o $Output

    if ($LASTEXITCODE -ne 0) {
        throw "Download failed: $Url"
    }
}

Download-IfMissing `
    "https://github.com/Ameliorated-LLC/trusted-uninstaller-cli/releases/download/0.8.4/AME-Beta-v0.8.4.exe" `
    $D

Download-IfMissing `
    "https://github.com/meetrevision/playbook/releases/download/26.04/Revi-PB-26.04.apbx" `
    $D

Download-IfMissing `
    "https://download.msi.com/uti_exe/desktop/MSI-Center.zip" `
    $D

Download-IfMissing `
    "https://github.com/MateuszKrawczuk/QtEmu/releases/download/2.1.1/qtemu.exe" `
    $D

Download-IfMissing `
    "https://us.download.nvidia.com/Windows/616.56/616.56-desktop-win10-win11-64bit-international-dch-whql.exe" `
    $D