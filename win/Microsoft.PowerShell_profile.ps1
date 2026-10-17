# Aliases
Set-Alias ll Get-ChildItem
Set-Alias touch New-Item
Set-Alias which Get-Command
function grep {
    param(
        [string]$Pattern,
        [string]$Path = "."
    )

    Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue |
        Select-String $Pattern
}
function find {
    param(
        [string]$Path = ".",
        [string]$Name = "*"
    )

    Get-ChildItem -Path $Path -Recurse -Filter $Name -File -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
}
function src_profile {
    . $PROFILE
}

# Environment variables
$env:EDITOR = "code"

# Custom function
function cproj {
    Set-Location "C:\Projects"
}

#
function fpush {
    git status

    $confirm = Read-Host "Do you want to force push? (y/N)"

    if ($confirm -ne "y") {
        Write-Host "Cancelled."
        return
    }

    git add .

    $message = Read-Host "Commit message"

    git commit -m $message

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Commit failed. Force push cancelled."
        return
    }

    git push origin main
}
