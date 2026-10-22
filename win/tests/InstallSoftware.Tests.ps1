# InstallSoftware.Tests.ps1 - Pester tests for install-software.ps1
#
# Covers the software install flow and the ~/.dotfiles/software.state.json
# inventory record. scoop and winget are replaced with shim functions that
# record calls and return canned output, so nothing touches the real system.

Describe "install-software (Pester)" {
    BeforeAll {
        $testsRoot   = Split-Path $PSCommandPath -Parent
        $winRoot     = Split-Path $testsRoot -Parent
        $installerPs = Join-Path $winRoot 'install-software.ps1'

        # Load functions via AST (skip main)
        $tokens = $null; $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($installerPs, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors) { throw "Parse errors in install-software.ps1: $parseErrors" }
        $functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
        foreach ($fn in $functions) { Invoke-Expression $fn.Extent.Text }
        . (Join-Path $winRoot 'lib\common.ps1')
    }

    BeforeEach {
        # Isolated temp root per test
        $script:TempRoot = Join-Path $env:TEMP ("sw-tests-" + [guid]::NewGuid().ToString('N'))
        $script:Config = @{
            Downloads   = Join-Path $script:TempRoot 'Downloads'
            StateDir    = Join-Path $script:TempRoot '.dotfiles'
            StateFile   = Join-Path $script:TempRoot '.dotfiles\software.state.json'
            PackageFile = Join-Path $winRoot 'package.txt'
            QtEmu       = 'https://example.invalid/qtemu.exe'
        }
        $script:Software = [System.Collections.Generic.List[object]]::new()
        $script:Unattended = $true   # main must not pause in tests

        # Tools visible to the code under test
        $script:Present = @()      # commands Get-Command should 'find'
        $script:ScoopCalls = [System.Collections.Generic.List[string]]::new()
        $script:ScoopApps = @()    # packages the scoop shim reports installed
        $script:ScoopBroken = @()  # packages scoop lists but has failed to install
        $script:ScoopBuckets = @()
        $script:ScoopFailOn = $null
        $script:WingetCalls = [System.Collections.Generic.List[string]]::new()
        $script:WingetApps = @()
        $script:WingetFailOn = $null

        function global:scoop {
            $cmd = @($args)[0]
            $arg = @($args)[1]
            $script:ScoopCalls.Add("$cmd $arg")
            $global:LASTEXITCODE = 0
            switch ($cmd) {
                'list' {
                    if ($script:ScoopApps -contains $arg) { Write-Output $arg }
                    if ($script:ScoopBroken -contains $arg) { Write-Output "$arg  Install failed" }
                }
                'prefix' {
                    if ($script:ScoopApps -contains $arg) { Write-Output (Join-Path $env:TEMP "$arg\current") }
                    else { $global:LASTEXITCODE = 1 }
                }
                'bucket' {
                    if ($arg -eq 'list') { $script:ScoopBuckets }
                    elseif ($arg -eq 'add') { $script:ScoopBuckets += @($args)[2] }
                }
                'install' {
                    if ($script:ScoopFailOn -and $arg -eq $script:ScoopFailOn) { $global:LASTEXITCODE = 1; return }
                    $script:ScoopApps += $arg
                }
            }
        }

        function global:winget {
            $a = @($args)
            $script:WingetCalls.Add(($a -join ' '))
            $global:LASTEXITCODE = 0
            $idIndex = [array]::IndexOf($a, '--id')
            $id = if ($idIndex -ge 0) { $a[$idIndex + 1] } else { $null }
            switch ($a[0]) {
                'list' { if ($id -and $script:WingetApps -contains $id) { Write-Output $id } }
                'install' {
                    if ($script:WingetFailOn -and $id -eq $script:WingetFailOn) { $global:LASTEXITCODE = 1; return }
                    if ($id) { $script:WingetApps += $id }
                }
            }
        }
    }

    AfterEach {
        Remove-Item function:global:scoop, function:global:winget -ErrorAction SilentlyContinue
        Remove-Item $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Parsing and loading" {
        It "loads functions from install-software.ps1" {
            Get-Command Install-ScoopPackages -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Install-WingetPackages -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Install-Software -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Add-SoftwareRecord -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Save-SoftwareState -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
    }

    Context "Software record" {
        It "Add-SoftwareRecord appends name, tool, result and timestamp" {
            Add-SoftwareRecord -Name 'git' -Tool 'scoop' -Result 'already-present'
            Add-SoftwareRecord -Name 'fzf' -Tool 'scoop' -Result 'installed'

            $script:Software.Count | Should Be 2
            $script:Software[0].name | Should Be 'git'
            $script:Software[0].tool | Should Be 'scoop'
            $script:Software[0].result | Should Be 'already-present'
            $script:Software[1].name | Should Be 'fzf'
            { [datetime]$script:Software[1].at } | Should Not Throw
        }

        It "Save-SoftwareState writes the inventory as JSON" {
            Add-SoftwareRecord -Name 'git' -Tool 'scoop' -Result 'installed'
            Add-SoftwareRecord -Name 'Brave.Brave' -Tool 'winget' -Result 'failed'
            Save-SoftwareState

            Test-Path $Config.StateFile | Should Be $true
            $json = Get-Content $Config.StateFile -Raw | ConvertFrom-Json
            @($json).Count | Should Be 2
            @($json)[0].name | Should Be 'git'
            @($json)[0].result | Should Be 'installed'
            @($json)[1].name | Should Be 'Brave.Brave'
            @($json)[1].tool | Should Be 'winget'
        }

        It "Save-SoftwareState writes an empty array when nothing was recorded" {
            Save-SoftwareState

            Test-Path $Config.StateFile | Should Be $true
            $json = Get-Content $Config.StateFile -Raw | ConvertFrom-Json
            @($json).Count | Should Be 0
        }

        It "Save-SoftwareState creates the state directory" {
            Test-Path $Config.StateDir | Should Be $false
            Save-SoftwareState
            Test-Path $Config.StateDir | Should Be $true
        }
    }

    Context "Install-ScoopPackages" {
        It "records already-present packages and installs nothing" {
            $script:ScoopApps = @('git', 'fzf', 'glazewm', 'obs-studio', 'zed', 'zellij', 'vscode', 'dotnet-sdk-lts', 'python312', 'yazi', 'neatdownloadmanager')
            $script:ScoopBuckets = @('extras', 'versions', 'java')

            Install-ScoopPackages

            @($script:ScoopCalls | Where-Object { $_ -like 'install*' }).Count | Should Be 0
            $script:Software.Count | Should Be 11   # git + 10 packages
            @($script:Software | Where-Object result -ne 'already-present').Count | Should Be 0
        }

        It "installs missing packages and records them as installed" {
            Install-ScoopPackages

            $script:ScoopCalls | Should Not BeNullOrEmpty
            ($script:ScoopCalls -contains 'install git') | Should Be $true
            foreach ($package in 'fzf', 'glazewm', 'obs-studio', 'zed', 'zellij', 'vscode', 'dotnet-sdk-lts', 'python312', 'yazi', 'neatdownloadmanager') {
                ($script:ScoopCalls -contains "install $package") | Should Be $true
            }
            $script:Software.Count | Should Be 11
            @($script:Software | Where-Object result -ne 'installed').Count | Should Be 0
            $script:ScoopBuckets -contains 'extras' | Should Be $true
        }

        It "retries a package whose previous install failed" {
            $script:ScoopBroken = @('git')

            Install-ScoopPackages

            ($script:ScoopCalls -contains 'install git') | Should Be $true
            @($script:Software | Where-Object { $_.name -eq 'git' -and $_.result -eq 'installed' }).Count | Should Be 1
        }

        It "records a failed install and keeps going" {
            $script:ScoopFailOn = 'obs-studio'

            Install-ScoopPackages

            $failed = @($script:Software | Where-Object result -eq 'failed')
            $failed.Count | Should Be 1
            $failed[0].name | Should Be 'obs-studio'
            $failed[0].tool | Should Be 'scoop'
            # Everything after obs-studio still installed
            @($script:Software | Where-Object { $_.name -eq 'zed' -and $_.result -eq 'installed' }).Count | Should Be 1
        }
    }

    Context "Install-WingetPackages" {
        It "records already-present and newly installed packages" {
            $script:WingetApps = @('Brave.Brave')

            Install-WingetPackages

            $script:Software.Count | Should Be 5
            @($script:Software | Where-Object { $_.name -eq 'Brave.Brave' }).Count | Should Be 1
            @($script:Software | Where-Object { $_.name -eq 'Brave.Brave' -and $_.result -eq 'already-present' }).Count | Should Be 1
            @($script:Software | Where-Object { $_.name -eq 'Roblox.Roblox' -and $_.result -eq 'installed' }).Count | Should Be 1
        }

        It "records a failed install and keeps going" {
            $script:WingetFailOn = 'Roblox.Roblox'

            Install-WingetPackages

            $failed = @($script:Software | Where-Object result -eq 'failed')
            $failed.Count | Should Be 1
            $failed[0].name | Should Be 'Roblox.Roblox'
            $failed[0].tool | Should Be 'winget'
            # The rest still installed
            @($script:Software | Where-Object { $_.result -eq 'installed' }).Count | Should Be 4
        }
    }

    Context "Install-Software" {
        It "checks every package but skips installers when the expected commands are present" {
            $script:Present = @('git', 'fzf', 'zed', 'code')
            $script:ScoopApps = @('git', 'fzf', 'glazewm', 'obs-studio', 'zed', 'zellij', 'vscode', 'dotnet-sdk-lts', 'python312', 'yazi', 'neatdownloadmanager')
            $script:WingetApps = @('Brave.Brave', 'BlenderFoundation.Blender.LTS.4.5', 'xpf0000.FlyEnv', 'HiBitSoftware.HiBitUninstaller', 'Roblox.Roblox')
            Mock -CommandName Get-Command -MockWith {
                param($Name)
                if ($script:Present -contains $Name) { [pscustomobject]@{ Name = $Name; Source = "C:\scoop\$Name.exe" } }
            }
            Mock -CommandName Start-Process -MockWith {}

            Install-Software

            @($script:ScoopCalls | Where-Object { $_ -like 'install*' }).Count | Should Be 0
            @($script:WingetCalls | Where-Object { $_ -like 'install*' }).Count | Should Be 0
            $script:Software.Count | Should Be 16
            @($script:Software | Where-Object result -ne 'already-present').Count | Should Be 0
            Assert-MockCalled Start-Process -Times 0 -Exactly -Scope It
        }

        It "installs packages and the external installer when something is missing" {
            $script:Present = @('git')   # fzf/zed/code missing -> full install
            Mock -CommandName Get-Command -MockWith {
                param($Name)
                if ($script:Present -contains $Name) { [pscustomobject]@{ Name = $Name; Source = "C:\scoop\$Name.exe" } }
            }
            Mock -CommandName Get-RemoteFile -MockWith {
                param($Url, $Directory)
                New-Item -ItemType Directory -Path $Directory -Force | Out-Null
                $file = Join-Path $Directory ([IO.Path]::GetFileName($Url))
                Set-Content -Path $file -Value 'stub'
                $file
            }
            Mock -CommandName Start-Process -MockWith {}

            Install-Software

            ($script:ScoopCalls -contains 'install git') | Should Be $true
            $wingetInstalls = @($script:WingetCalls | Where-Object { $_ -like 'install*' })
            $wingetInstalls.Count | Should Be 5
            Assert-MockCalled Start-Process -Times 1 -Exactly -Scope It
            $external = @($script:Software | Where-Object tool -eq 'installer')
            $external.Count | Should Be 1
            $external[0].name | Should Be 'qtemu.exe'
            $external[0].result | Should Be 'installed'
        }
    }

    Context "main" {
        It "saves the state file and summary even when Install-Software throws" {
            Mock -CommandName Install-Software -MockWith { throw 'boom' }

            { main } | Should Not Throw

            Test-Path $Config.StateFile | Should Be $true
            $json = Get-Content $Config.StateFile -Raw | ConvertFrom-Json
            @($json).Count | Should Be 0
        }

        It "returns early without a state file when scoop is missing" {
            Mock -CommandName Get-Command -MockWith { $null }
            Mock -CommandName Install-Software -MockWith {}

            main

            Assert-MockCalled Install-Software -Times 0 -Exactly -Scope It
            Test-Path $Config.StateFile | Should Be $false
        }
    }
}
