# Bootstrap.Tests.ps1 - Pester tests for bootstrap.ps1
#
# Covers the bootstrap stages (environment, scoop, winget, updates, drivers,
# profile link) plus the debloat flow that used to live in Debloat.Tests.ps1.
# scoop and winget are replaced with shim functions that record calls and
# return canned output, so nothing touches the real system.

Describe "bootstrap (Pester)" {
    BeforeAll {
        $testsRoot    = Split-Path $PSCommandPath -Parent
        $winRoot      = Split-Path $testsRoot -Parent
        $bootstrapPs  = Join-Path $winRoot 'bootstrap.ps1'
        $ameCli       = Join-Path $winRoot 'ame-cli.ps1'

        # Load functions via AST (skip main)
        $tokens = $null; $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($bootstrapPs, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors) { throw "Parse errors in bootstrap.ps1: $parseErrors" }
        $functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
        foreach ($fn in $functions) { Invoke-Expression $fn.Extent.Text }
        . (Join-Path $winRoot 'lib\common.ps1')
        . $ameCli

        # Complete-Bootstrap uses $PSScriptRoot, which is empty in AST-loaded
        # functions; reload it with the path bound to the real win/ folder.
        $script:SourcePath = Join-Path $winRoot 'Microsoft.PowerShell_profile.ps1'
        $cbAst = $functions | Where-Object Name -eq 'Complete-Bootstrap'
        Invoke-Expression $cbAst.Extent.Text.Replace('$PSScriptRoot', "'$winRoot'")

        # Stubs so Pester can mock commands that may not exist on this host.
        # The parameters must mirror the real cmdlets: Pester -ParameterFilter
        # only sees bound parameters, so a bare stub would swallow -Install.
        # Both stay mocked so the tests can prove the update check never
        # reaches for a Windows Update module or installs anything.
        function Get-WindowsUpdate {
            param(
                [switch]$Install,
                [switch]$Download,
                [switch]$AcceptAll,
                [switch]$IgnoreReboot,
                [string]$Criteria
            )
        }
        function Install-Module { }
    }

    BeforeEach {
        # Isolated temp root per test (.NET calls: leaked mocks from earlier
        # contexts can intercept cmdlets inside BeforeEach in Pester 3.4)
        $script:TempRoot = Join-Path $env:TEMP ("bs-tests-" + [guid]::NewGuid().ToString('N'))
        [System.IO.Directory]::CreateDirectory($script:TempRoot) | Out-Null
        $script:Config = @{
            Downloads     = $script:TempRoot
            StateDir      = $script:TempRoot
            StateFile     = Join-Path $script:TempRoot 'bootstrap.state.json'
            ReviPlaybook  = 'https://example.invalid/Revi-PB.apbx'
            CliStandalone = 'https://example.invalid/CLI-Standalone.zip'
            MsiCenter     = 'https://example.invalid/MSI-Center.zip'
            NvidiaDriver  = 'https://example.invalid/nvidia.exe'
            UpdateSettings = 'ms-settings:windowsupdate'
        }
        $script:ProfilePath = Join-Path $script:TempRoot 'profile.ps1'
        $script:ProfilePathExplicit = $true   # tests pass -ProfilePath explicitly
        $script:Unattended = $true   # main must not pause in tests
        $script:SkipUpdateCheck = $false
        $script:UpdateCheckResult = $null

        # Shared prompt state
        $script:Asked = [System.Collections.Generic.List[string]]::new()
        $script:AnswerQueue = [System.Collections.Generic.Queue[bool]]::new()

        # Tools visible to the code under test
        $script:ScoopCalls = [System.Collections.Generic.List[string]]::new()
        $script:ScoopApps = @()
        $script:ScoopBuckets = @()
        $script:ScoopFailOn = $null
        $script:WingetCalls = [System.Collections.Generic.List[string]]::new()
        $script:WingetFailOn = $null

        function global:scoop {
            $cmd = @($args)[0]
            $arg = @($args)[1]
            $script:ScoopCalls.Add("$cmd $arg")
            $global:LASTEXITCODE = 0
            switch ($cmd) {
                'list' {
                    if ($script:ScoopApps -contains $arg) { Write-Output $arg }
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
        }
    }

    AfterEach {
        Remove-Item function:global:scoop, function:global:winget -ErrorAction SilentlyContinue
        if ([System.IO.Directory]::Exists($script:TempRoot)) {
            [System.IO.Directory]::Delete($script:TempRoot, $true)
        }
    }

    Context "Parsing and loading" {
        It "loads functions from bootstrap.ps1" {
            Get-Command Initialize-Scoop -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Initialize-Winget -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Repair-Winget -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Update-SessionPath -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Get-DefenderTogglesOn -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Disable-Defender -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            # The Defender stage is manual: the scripted helpers are gone.
            Get-Command Set-DefenderPolicy -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Set-TamperProtectionOff -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Resolve-DefenderManually -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Test-WindowsUpdates -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Get-PendingWindowsUpdates -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Get-UpdateSizeMb -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Get-UpdateSizeTotal -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Format-UpdateSize -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Invoke-Debloat -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Invoke-Drivers -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Complete-Bootstrap -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
    }

    Context "Stage markers" {
        BeforeEach {
            Mock -CommandName Test-Path -MockWith { param($Path) [System.IO.File]::Exists("$Path") -or [System.IO.Directory]::Exists("$Path") }
            Mock -CommandName Set-Content -MockWith { param($Path, $Value) [System.IO.File]::WriteAllText("$Path", "$Value") }
        }

        It "Complete-Stage writes a marker Test-Stage finds" {
            Complete-Stage 'debloat'
            Test-Stage 'debloat' | Should Be $true
            Test-Stage 'drivers' | Should Be $false
        }
    }

    Context "Initialize-Environment" {
        It "skips everything when policy and directories are already set" {
            Mock -CommandName Get-ExecutionPolicy -MockWith { [pscustomobject]@{ Scope = 'CurrentUser'; ExecutionPolicy = 'RemoteSigned' } }
            Mock -CommandName Test-Path -MockWith { $true }
            Mock -CommandName Set-ExecutionPolicy -MockWith {}
            Mock -CommandName New-Item -MockWith {}

            Initialize-Environment

            Assert-MockCalled Set-ExecutionPolicy -Times 0 -Exactly -Scope It
            Assert-MockCalled New-Item -Times 0 -Exactly -Scope It
        }

        It "creates missing directories" {
            Mock -CommandName Get-ExecutionPolicy -MockWith { [pscustomobject]@{ Scope = 'CurrentUser'; ExecutionPolicy = 'RemoteSigned' } }
            Mock -CommandName Test-Path -MockWith { $false }
            Mock -CommandName Set-ExecutionPolicy -MockWith {}
            $script:Created = [System.Collections.Generic.List[string]]::new()
            Mock -CommandName New-Item -MockWith { param($ItemType, $Path) $script:Created.Add("$ItemType $Path") }

            Initialize-Environment

            Assert-MockCalled Set-ExecutionPolicy -Times 0 -Exactly -Scope It
            @($script:Created | Where-Object { $_ -like 'Directory *' }).Count | Should Be 2
        }
    }

    Context "Initialize-Scoop" {
        It "installs git only and leaves other packages to install-software.ps1" {
            Initialize-Scoop

            $installs = @($script:ScoopCalls | Where-Object { $_ -like 'install*' })
            $installs.Count | Should Be 1
            ($script:ScoopCalls -contains 'install git') | Should Be $true
            $script:ScoopBuckets -contains 'main' | Should Be $true
        }

        It "skips when scoop, the main bucket and git are already present" {
            $script:ScoopBuckets = @('main')
            $script:ScoopApps = @('git')

            Initialize-Scoop

            @($script:ScoopCalls | Where-Object { $_ -like 'install*' }).Count | Should Be 0
            @($script:ScoopCalls | Where-Object { $_ -like 'bucket add*' }).Count | Should Be 0
        }

        It "throws when git cannot be installed" {
            $script:ScoopFailOn = 'git'
            { Initialize-Scoop } | Should Throw
        }
    }

    Context "Initialize-Winget" {
        It "attempts repair then throws when winget stays missing" {
            Mock -CommandName Get-Command -MockWith { $null } -ParameterFilter { $Name -eq 'winget' }
            Mock -CommandName Repair-Winget -MockWith {}

            { Initialize-Winget } | Should Throw

            # Repair ran once, but winget was still missing afterwards.
            Assert-MockCalled Repair-Winget -Times 1 -Exactly -Scope It
        }

        It "skips repair when winget is already present" {
            Mock -CommandName Get-Command -MockWith { [pscustomobject]@{ Name = 'winget' } } -ParameterFilter { $Name -eq 'winget' }
            Mock -CommandName Repair-Winget -MockWith {}

            { Initialize-Winget } | Should Not Throw

            Assert-MockCalled Repair-Winget -Times 0 -Exactly -Scope It
        }

        It "refreshes sources when winget is present" {
            Mock -CommandName Get-Command -MockWith { [pscustomobject]@{ Name = 'winget' } } -ParameterFilter { $Name -eq 'winget' }
            { Initialize-Winget } | Should Not Throw
            @($script:WingetCalls | Where-Object { $_ -like 'source update*' }).Count | Should Be 1
        }
    }

    Context "Repair-Winget" {
        It "skips when winget already resolves" {
            Mock -CommandName Get-Command -MockWith { [pscustomobject]@{ Name = 'winget' } } -ParameterFilter { $Name -eq 'winget' }

            { Repair-Winget } | Should Not Throw
        }
    }

    Context "Windows update check" {
        BeforeEach {
            # Pester 3.4 leaks Test-Path/Set-Content mocks from earlier
            # contexts; re-pin them to real filesystem behavior here.
            Mock -CommandName Test-Path -MockWith { param($Path) [System.IO.File]::Exists("$Path") -or [System.IO.Directory]::Exists("$Path") }
            Mock -CommandName Set-Content -MockWith { param($Path, $Value) [System.IO.File]::WriteAllText("$Path", "$Value") }

            $script:UpdateCheckResult = $null
            $script:Started = [System.Collections.Generic.List[string]]::new()

            Mock -CommandName Get-PendingWindowsUpdates -MockWith { @() }
            Mock -CommandName Show-PendingUpdates -MockWith {}
            Mock -CommandName Start-Process -MockWith { param($FilePath) $script:Started.Add("$FilePath") }
            Mock -CommandName Confirm-Step -MockWith {
                param($Question)
                $script:Asked.Add($Question)
                if ($script:AnswerQueue.Count -gt 0) { [bool]$script:AnswerQueue.Dequeue() } else { $true }
            }
        }

        It "reports up to date when nothing is pending" {
            Test-WindowsUpdates

            $script:UpdateCheckResult.upToDate | Should Be $true
            $script:UpdateCheckResult.pendingCount | Should Be 0
        }

        It "reports the pending updates without installing them" {
            Mock -CommandName Get-PendingWindowsUpdates -MockWith {
                @(
                    [pscustomobject]@{ Title = 'Update A'; Size = 1048576; KB = '1234'; Mandatory = $false; Downloaded = $false },
                    [pscustomobject]@{ Title = 'Update B'; Size = 2097152; KB = '5678'; Mandatory = $false; Downloaded = $false }
                )
            }

            Test-WindowsUpdates

            $script:UpdateCheckResult.upToDate | Should Be $false
            $script:UpdateCheckResult.pendingCount | Should Be 2
            $script:UpdateCheckResult.pendingSizeMb | Should Be 3
            Assert-MockCalled Show-PendingUpdates -Times 1 -Exactly -Scope It
        }

        It "never installs an update" {
            Mock -CommandName Get-PendingWindowsUpdates -MockWith {
                @( [pscustomobject]@{ Title = 'Update X'; Size = 1048576; KB = '1234'; Mandatory = $false; Downloaded = $false } )
            }
            # Declared so the assertions below can prove none of them ran.
            Mock -CommandName Get-WindowsUpdate -MockWith { }
            Mock -CommandName Install-Module -MockWith { }
            Mock -CommandName Install-PackageProvider -MockWith { }
            Mock -CommandName Set-PSRepository -MockWith { }

            Test-WindowsUpdates

            # No install path at all: not the module, not the cmdlet, and no
            # package provider or repository is touched either.
            Assert-MockCalled Get-WindowsUpdate -Times 0 -Exactly -Scope It
            Assert-MockCalled Install-Module -Times 0 -Exactly -Scope It
            Assert-MockCalled Install-PackageProvider -Times 0 -Exactly -Scope It
            Assert-MockCalled Set-PSRepository -Times 0 -Exactly -Scope It
        }

        It "never asks the user to install the updates" {
            Mock -CommandName Get-PendingWindowsUpdates -MockWith {
                @( [pscustomobject]@{ Title = 'Update X'; Size = 1048576; KB = '1234'; Mandatory = $false; Downloaded = $false } )
            }

            Test-WindowsUpdates

            $script:Asked.Count | Should Be 0
            Assert-MockCalled Confirm-Step -Times 0 -Exactly -Scope It
        }

        It "opens the Windows Update page for the user" {
            $script:Unattended = $false
            Mock -CommandName Get-PendingWindowsUpdates -MockWith {
                @( [pscustomobject]@{ Title = 'Update X'; Size = 1048576; KB = '1234'; Mandatory = $false; Downloaded = $false } )
            }

            Test-WindowsUpdates

            $script:Started.Count | Should Be 1
            $script:Started[0] | Should Match 'windowsupdate'
        }

        It "does not open the Windows Update page when unattended" {
            $script:Unattended = $true
            Mock -CommandName Get-PendingWindowsUpdates -MockWith {
                @( [pscustomobject]@{ Title = 'Update X'; Size = 1048576; KB = '1234'; Mandatory = $false; Downloaded = $false } )
            }

            Test-WindowsUpdates

            $script:Started.Count | Should Be 0
        }

        It "skips the check when -SkipUpdateCheck is passed" {
            $script:SkipUpdateCheck = $true

            Test-WindowsUpdates

            Assert-MockCalled Get-PendingWindowsUpdates -Times 0 -Exactly -Scope It
            $script:UpdateCheckResult.skipped | Should Be $true
        }

        It "records the check result in the state file" {
            Test-WindowsUpdates

            Save-CompletionState

            Test-Path $Config.StateFile | Should Be $true
            $state = Get-Content $Config.StateFile -Raw | ConvertFrom-Json
            $state.windowsUpdate.upToDate | Should Be $true
            $state.windowsUpdate.pendingCount | Should Be 0
        }
    }


    Context "Format-UpdateSize" {
        It "formats unit-suffixed sizes" {
            Format-UpdateSize -Update ([pscustomobject]@{ Size = '44MB' }) | Should Be ('{0:N1} MB' -f 44)
        }

        It "formats raw byte counts" {
            Format-UpdateSize -Update ([pscustomobject]@{ Size = 1048576 }) | Should Be ('{0:N1} MB' -f 1)
        }

        It "adds up sizes that arrive as an array" {
            Format-UpdateSize -Update ([pscustomobject]@{ Size = @(1048576, 524288) }) | Should Be ('{0:N1} MB' -f 1.5)
        }

        It "returns an empty string when the size is missing" {
            Format-UpdateSize -Update ([pscustomobject]@{ Size = $null }) | Should Be ''
        }
    }

    Context "Get-UpdateSizeTotal" {
        It "adds up the sizes of the pending updates" {
            $updates = @(
                [pscustomobject]@{ Title = 'Update A'; Size = 1048576 }
                [pscustomobject]@{ Title = 'Update B'; Size = 2097152 }
            )

            Get-UpdateSizeTotal -Updates $updates | Should Be 3
        }

        It "ignores updates without a size" {
            $updates = @(
                [pscustomobject]@{ Title = 'Update A'; Size = 1048576 }
                [pscustomobject]@{ Title = 'Update B'; Size = $null }
            )

            Get-UpdateSizeTotal -Updates $updates | Should Be 1
        }
    }

    Context "Invoke-Drivers" {
        It "skips driver downloads when all devices are healthy" {
            Mock -CommandName Get-CimInstance -MockWith { [pscustomobject]@{ Manufacturer = 'MSI'; Model = 'Prestige' } }
            Mock -CommandName Get-PnpDevice -MockWith { @() }
            Mock -CommandName Get-RemoteFile -MockWith { $script:Downloads.Add($Url); Join-Path $Directory ([IO.Path]::GetFileName($Url)) }
            $script:Downloads = [System.Collections.Generic.List[string]]::new()

            Invoke-Drivers

            $script:Downloads.Count | Should Be 0
        }
    }

    Context "Disable-Defender" {
        BeforeEach {
            $script:SettingsShown = 0
            Mock -CommandName Show-DefenderSettings -MockWith { $script:SettingsShown++ }
            Mock -CommandName Confirm-Step -MockWith {}
            Mock -CommandName Set-MpPreference -MockWith {}
        }

        It "skips when all toggles are already off" {
            Mock -CommandName Get-DefenderTogglesOn -MockWith { @() }

            $ok = Disable-Defender

            $ok | Should Be $true
            $script:SettingsShown | Should Be 0
            Assert-MockCalled Confirm-Step -Times 0 -Exactly -Scope It
            Assert-MockCalled Set-MpPreference -Times 0 -Exactly -Scope It
        }

        It "hands the toggles to Windows Security and reports the result" {
            Mock -CommandName Get-DefenderTogglesOn -MockWith { @('Real-time protection') }

            $ok = Disable-Defender

            $ok | Should Be $false
            $script:SettingsShown | Should BeGreaterThan 0
            # Manual by design: nothing is written to the platform.
            Assert-MockCalled Set-MpPreference -Times 0 -Exactly -Scope It
        }
    }

    Context "Invoke-Debloat" {
        BeforeEach {
            # Stage markers use REAL files in the temp state dir; Test-Path,
            # Set-Content and New-Item are deliberately not mocked here except
            # for real-behavior pins - Pester 3.4 leaks mocks across contexts.
            Mock -CommandName Test-Path -MockWith { param($Path) [System.IO.File]::Exists("$Path") -or [System.IO.Directory]::Exists("$Path") }
            Mock -CommandName Set-Content -MockWith { param($Path, $Value) [System.IO.File]::WriteAllText("$Path", "$Value") }

            $script:Marker = Join-Path $script:Config.StateDir 'stage-debloat.done'
            [System.IO.File]::Delete($script:Marker)
            $script:CliDownloads = $script:TempRoot   # keep ame-cli out of the real Downloads

            Mock -CommandName Get-RemoteFile -MockWith { param($Url,$Directory) $script:Downloads.Add($Url); Join-Path $Directory (Split-Path $Url -Leaf) }
            Mock -CommandName Test-Artifact -MockWith { $script:ArtifactOk }
            Mock -CommandName Confirm-Step -MockWith { param($Question) $script:Asked.Add($Question); if ($script:AnswerQueue.Count -gt 0) { [bool]$script:AnswerQueue.Dequeue() } else { $true } }
            Mock -CommandName Set-MpPreference -MockWith { $script:DefenderCalls++ }
            Mock -CommandName Get-MpComputerStatus -MockWith { [pscustomobject]@{ RealTimeProtectionEnabled = $script:RealTimeProtection } }
            Mock -CommandName Get-DefenderTogglesOn -MockWith { @() }
            Mock -CommandName Start-Process -MockWith { param($FilePath,$ArgumentList,[switch]$Wait,[switch]$NoNewWindow,[switch]$PassThru) $script:Processes.Add(@{FilePath=$FilePath; ArgumentList=$ArgumentList}); if ($PassThru) { [pscustomobject]@{ExitCode=0} } }
            Mock -CommandName Expand-Archive -MockWith { $script:ArchiveRuns++; $script:Extracted.Cli = $true }
            Mock -CommandName Expand-SevenZip -MockWith { $script:SevenZipRuns++; $script:Extracted.Playbook = $true }
            Mock -CommandName Get-ChildItem -MockWith {
                param($Path,[switch]$Recurse,$Filter)
                switch -Wildcard ($Filter) {
                    'TrustedUninstaller.CLI.exe' { if ($script:Extracted.Cli) { [pscustomobject]@{FullName="$Path\TrustedUninstaller.CLI.exe"; Directory=[pscustomobject]@{FullName=$Path}} } }
                    'playbook.conf' { if ($script:Extracted.Playbook) { [pscustomobject]@{FullName="$Path\playbook.conf"; Directory=[pscustomobject]@{FullName=$Path}} } }
                }
            }

            $script:Processes = [System.Collections.Generic.List[object]]::new()
            $script:Downloads = [System.Collections.Generic.List[string]]::new()
            $script:ArchiveRuns = 0
            $script:SevenZipRuns = 0
            $script:DefenderCalls = 0
            $script:RealTimeProtection = $false
            $script:ArtifactOk = $true
            $script:Extracted = @{ Cli = $false; Playbook = $false }
        }

        It "happy path applies with 15 options" {
            $script:AnswerQueue.Enqueue($true)
            { Invoke-Debloat } | Should Not Throw
            $script:Downloads.Count | Should Be 3
            $script:Processes.Count | Should Be 1
            $script:Processes[0].FilePath | Should Match 'TrustedUninstaller\.CLI\.exe'
            ($script:Processes[0].ArgumentList | Measure-Object).Count | Should Be 16
            ($script:Processes[0].ArgumentList -contains 'browser-brave') | Should Be $false
            ($script:Processes[0].ArgumentList -contains 'remove-edge') | Should Be $false
            $script:Asked.Count | Should Be 1
            Test-Path $script:Marker | Should Be $true
        }

        It "declining confirmation warns and continues (no throw)" {
            $script:AnswerQueue.Enqueue($false)
            { Invoke-Debloat } | Should Not Throw
            $script:Processes.Count | Should Be 0
            Test-Path $script:Marker | Should Be $false
        }

        It "missing artifacts throws" {
            $script:ArtifactOk = $false
            { Invoke-Debloat } | Should Throw
        }

        It "blocks before the CLI when the Defender toggles stay on" {
            Mock -CommandName Get-DefenderTogglesOn -MockWith { @('Tamper protection') }

            { Invoke-Debloat } | Should Throw

            # The Windows Security window may be opened for the user, but the
            # TrustedUninstaller CLI must never run.
            $cliRuns = @($script:Processes | Where-Object { $_.FilePath -match 'TrustedUninstaller' })
            $cliRuns.Count | Should Be 0
            Test-Path $script:Marker | Should Be $false
        }

        It "stage marker skips entirely" {
            Set-Content -Path $script:Marker -Value 'test'
            { Invoke-Debloat } | Should Not Throw
            $script:Downloads.Count | Should Be 0
            $script:Processes.Count | Should Be 0
        }
    }

    Context "Complete-Bootstrap" {
        BeforeEach {
            # Pester 3.4 leaks Test-Path/Set-Content mocks from earlier
            # contexts; re-pin them to real filesystem behavior here.
            Mock -CommandName Test-Path -MockWith { param($Path) [System.IO.File]::Exists("$Path") -or [System.IO.Directory]::Exists("$Path") }
            Mock -CommandName Set-Content -MockWith { param($Path, $Value) [System.IO.File]::WriteAllText("$Path", "$Value") }

            $script:Linked = $false
            $script:NewItems = [System.Collections.Generic.List[object]]::new()
            $script:GetItemPaths = [System.Collections.Generic.List[string]]::new()
            Mock -CommandName Get-Item -MockWith {
                param($Path)
                $script:GetItemPaths.Add("$Path")
                if ($script:Linked) {
                    [pscustomobject]@{
                        Path     = $Path
                        LinkType = 'SymbolicLink'
                        Target   = $script:SourcePath
                    }
                } else { $null }
            }
            Mock -CommandName New-Item -MockWith {
                param($ItemType, $Path, $Target)
                $script:NewItems.Add(@{ ItemType = $ItemType; Path = $Path; Target = $Target })
                $script:Linked = $true
            }
            Mock -CommandName Remove-Item -MockWith {}
        }

        It "skips when the profile is already linked and saves completion state" {
            $script:Linked = $true

            Complete-Bootstrap

            $script:NewItems.Count | Should Be 0
            Test-Path $Config.StateFile | Should Be $true
            (Get-Content $Config.StateFile -Raw | ConvertFrom-Json).status | Should Be 'complete'
        }

        It "creates the symlink and verifies it" {
            Complete-Bootstrap

            $link = @($script:NewItems | Select-Object -Last 1)[0]
            # -Target is a dynamic New-Item parameter the mock cannot capture.
            $link.ItemType | Should Be 'SymbolicLink'
            $link.Path | Should Be $script:ProfilePath
            # The explicitly passed -ProfilePath wins over the live $PROFILE.
            $script:GetItemPaths[0] | Should Be $script:ProfilePath
            Test-Path $Config.StateFile | Should Be $true
        }

        It 'checks and links the live $PROFILE when -ProfilePath was not passed' {
            $script:ProfilePathExplicit = $false

            Complete-Bootstrap

            # Both the initial check and the post-link verification used the
            # live $PROFILE of the running session.
            $script:GetItemPaths.Count | Should BeGreaterThan 0
            @($script:GetItemPaths | Where-Object { $_ -ne "$PROFILE" }).Count | Should Be 0
            @($script:NewItems | Where-Object { $_.ItemType -eq 'SymbolicLink' })[0].Path | Should Be "$PROFILE"
            (Get-Content $Config.StateFile -Raw | ConvertFrom-Json).profile | Should Be "$PROFILE"
        }

        It "throws when the link cannot be verified" {
            # New-Item runs but the link never appears
            Mock -CommandName New-Item -MockWith {}
            { Complete-Bootstrap } | Should Throw
        }
    }

    Context "main" {
        BeforeEach {
            # Pester 3.4 leaks Test-Path/Set-Content mocks from earlier
            # contexts; re-pin them to real filesystem behavior here.
            Mock -CommandName Test-Path -MockWith { param($Path) [System.IO.File]::Exists("$Path") -or [System.IO.Directory]::Exists("$Path") }
            Mock -CommandName Set-Content -MockWith { param($Path, $Value) [System.IO.File]::WriteAllText("$Path", "$Value") }

            $script:Order = [System.Collections.Generic.List[string]]::new()
            Mock -CommandName Start-Bootstrap -MockWith { $script:Order.Add('Start-Bootstrap') }
            Mock -CommandName Assert-Administrator -MockWith { $script:Order.Add('Assert-Administrator') }
            Mock -CommandName Initialize-Environment -MockWith { $script:Order.Add('Initialize-Environment') }
            Mock -CommandName Initialize-Scoop -MockWith { $script:Order.Add('Initialize-Scoop') }
            Mock -CommandName Initialize-Winget -MockWith { $script:Order.Add('Initialize-Winget') }
            Mock -CommandName Test-WindowsUpdates -MockWith { $script:Order.Add('Test-WindowsUpdates') }
            Mock -CommandName Invoke-Debloat -MockWith { $script:Order.Add('Invoke-Debloat') }
            Mock -CommandName Invoke-Drivers -MockWith { $script:Order.Add('Invoke-Drivers') }
            Mock -CommandName Complete-Bootstrap -MockWith { $script:Order.Add('Complete-Bootstrap') }
        }

        It "runs every stage in order" {
            main

            ($script:Order -join '>') | Should Be 'Start-Bootstrap>Assert-Administrator>Initialize-Environment>Initialize-Scoop>Initialize-Winget>Test-WindowsUpdates>Invoke-Debloat>Invoke-Drivers>Complete-Bootstrap'
        }

        It "saves recovery state when a stage fails" {
            Mock -CommandName Initialize-Scoop -MockWith { throw 'scoop is broken' }

            { main } | Should Not Throw

            Test-Path $Config.StateFile | Should Be $true
            (Get-Content $Config.StateFile -Raw | ConvertFrom-Json).status | Should Be 'failed'
            # Later stages never ran
            $script:Order -contains 'Complete-Bootstrap' | Should Be $false
        }
    }
}
