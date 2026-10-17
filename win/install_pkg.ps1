function scoop_init() {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host "Scoop is already installed."
        scoop update
    } else {
        Write-Host "Installing Scoop..."
        Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
    }
}
function scoop_install() {
    # --- BUCKETS ---
    scoop bucket add main
    scoop bucket add extras
    scoop bucket add versions

    # --- TOOLS ---
    scoop install git
    scoop install fzf
    scoop install glazewm
    scoop install obs-studio
    scoop install zed

    # --- PROGRAMMING ---
    scoop install zellij
    scoop install vscode
    scoop install dotnet-sdk-lts
}
# scoop_init
scoop_install

function download_winget() {
    winget install -e --id Brave.Brave
    winget install -e --id BlenderFoundation.Blender.LTS.4.5
    winget install -e --id xpf0000.FlyEnv
    winget install -e --id JavadMotallebi.NeatDownloadManager
    winget install -e --id HiBitSoftware.HiBitUninstaller
    winget install -e --id Roblox.Roblox
}
download_winget
