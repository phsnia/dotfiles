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
        function Restart-Computer { }
        # The Defender module does not expose every preference on every
        # build; a stub keeps the "nothing is written" assertion
        # host-independent.
        function Set-MpPreference {
            [CmdletBinding()]
            param(
                [bool]$DisableTamperProtection,
                [bool]$DisableRealtimeMonitoring,
                [bool]$DisableBehaviorMonitoring,
                [bool]$DisableIOAVProtection,
                [bool]$DisableBlockAtFirstSeen,
                [string]$MAPSReporting,
                [string]$SubmitSamplesConsent
            )
        }
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
            UpdateMaxRounds = 5
        }
        $script:ProfilePath = Join-Path $script:TempRoot 'profile.ps1'
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
            Get-Command Update-SessionPath -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Get-DefenderTogglesOn -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Invoke-DefenderCheck -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            # The old stage helper is gone: the simple check replaced it.
            Get-Command Disable-Defender -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            # The Defender stage is manual: the scripted helpers are gone.
            Get-Command Set-DefenderPolicy -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Set-TamperProtectionOff -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Resolve-DefenderManually -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Invoke-WindowsUpdates -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Search-WindowsUpdates -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Get-UpdateSummary -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Install-WindowsUpdates -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Test-RebootRequired -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            # The scan-and-report stage is gone: the stage installs now.
            Get-Command Test-WindowsUpdates -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Get-PendingWindowsUpdates -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            # The size helpers are gone: the summary carries the size.
            Get-Command Get-UpdateSizeMb -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Get-UpdateSizeTotal -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Format-UpdateSize -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            # The one-caller helpers were merged into their stage.
            Get-Command Repair-Winget -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Release-Search -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Show-PendingUpdates -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Start-Bootstrap -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Invoke-Debloat -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Invoke-Drivers -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Complete-Bootstrap -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            # The stage marker framework is gone: one marker, one stage.
            Get-Command Get-StageMarkerPath -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Test-Stage -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Complete-Stage -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            # The profile path resolution lives in the stage that links it.
            Get-Command Resolve-ProfilePath -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            # The winget repair has one route: the winget-cli release.
            Get-Command Install-WingetFromStore -ErrorAction SilentlyContinue | Should BeNullOrEmpty
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
            # One call creates every missing work directory.
            $script:Created.Count | Should Be 1
            $script:Created[0] | Should Match 'Directory'
            $script:Created[0] | Should Match ([regex]::Escape($Config.Downloads))
            $script:Created[0] | Should Match ([regex]::Escape($Config.StateDir))
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
        It "attempts the release repair then throws when winget stays missing" {
            Mock -CommandName Get-Command -MockWith { $null } -ParameterFilter { $Name -eq 'winget' }
            Mock -CommandName Install-WingetFromRelease -MockWith { $false }

            { Initialize-Winget } | Should Throw

            # The repair ran once, but winget was still missing afterwards.
            Assert-MockCalled Install-WingetFromRelease -Times 1 -Exactly -Scope It
        }

        It "skips the repair when winget is already present" {
            Mock -CommandName Get-Command -MockWith { [pscustomobject]@{ Name = 'winget' } } -ParameterFilter { $Name -eq 'winget' }
            Mock -CommandName Install-WingetFromRelease -MockWith { $false }

            { Initialize-Winget } | Should Not Throw

            Assert-MockCalled Install-WingetFromRelease -Times 0 -Exactly -Scope It
        }

        It "refreshes sources when winget is present" {
            Mock -CommandName Get-Command -MockWith { [pscustomobject]@{ Name = 'winget' } } -ParameterFilter { $Name -eq 'winget' }
            { Initialize-Winget } | Should Not Throw
            @($script:WingetCalls | Where-Object { $_ -like 'source update*' }).Count | Should Be 1
        }
    }

    Context "Windows update stage" {
        BeforeEach {
            # Pester 3.4 leaks Test-Path/Set-Content mocks from earlier
            # contexts; re-pin them to real filesystem behavior here.
            Mock -CommandName Test-Path -MockWith { param($Path) [System.IO.File]::Exists("$Path") -or [System.IO.Directory]::Exists("$Path") }
            Mock -CommandName Set-Content -MockWith { param($Path, $Value) [System.IO.File]::WriteAllText("$Path", "$Value") }

            $script:UpdateCheckResult = $null
            $script:Started = [System.Collections.Generic.List[string]]::new()
            $script:SearchCalls = 0
            $script:InstallCalls = [System.Collections.Generic.List[int]]::new()
            $script:Packages = @()
            $script:PackagesRepeat = $false
            $script:InstallOk = $true
            $script:RebootRequired = $false

            # One scan per round: the mock hands out the packages once and
            # reports an empty catalogue afterwards - that is what an
            # installed update looks like to the next scan.
            Mock -CommandName Search-WindowsUpdates -MockWith {
                $script:SearchCalls++
                $updates = $script:Packages
                if (-not $script:PackagesRepeat) { $script:Packages = @() }
                @{ Session = $null; Searcher = $null; Result = $null; Updates = $updates }
            }
            # The summary carries the display values the stage prints.
            Mock -CommandName Get-UpdateSummary -MockWith {
                param($Update)
                [pscustomobject]@{
                    UpdateID = $Update.UpdateID
                    Title    = $Update.Title
                    SizeMb   = $Update.SizeMb
                    KB       = $Update.KB
                }
            }
            Mock -CommandName Install-WindowsUpdates -MockWith {
                param($Search, $Summaries)
                $script:InstallCalls.Add(@($Summaries).Count)
                $results = @()
                foreach ($summary in @($Summaries)) {
                    $code = if ($script:InstallOk) { 2 } else { 4 }
                    $results += [pscustomobject]@{
                        Title          = $summary.Title
                        KB             = $summary.KB
                        ResultCode     = $code
                        HResult        = 0
                        RebootRequired = $script:RebootRequired
                        Succeeded      = ($code -eq 2)
                    }
                }
                $results
            }
            Mock -CommandName Test-RebootRequired -MockWith { $script:RebootRequired }
            Mock -CommandName Restart-Computer -MockWith { }
            Mock -CommandName Start-Process -MockWith { param($FilePath) $script:Started.Add("$FilePath") }
            Mock -CommandName Confirm-Step -MockWith {
                param($Question)
                $script:Asked.Add($Question)
                if ($script:AnswerQueue.Count -gt 0) { [bool]$script:AnswerQueue.Dequeue() } else { $true }
            }
        }

        It "reports up to date when the scan is empty" {
            Invoke-WindowsUpdates

            $script:UpdateCheckResult.upToDate | Should Be $true
            $script:UpdateCheckResult.pendingCount | Should Be 0
            $script:InstallCalls.Count | Should Be 0
        }

        It "installs exactly the scanned set" {
            $script:Packages = @(
                [pscustomobject]@{ UpdateID = 'a'; Title = 'Update A'; SizeMb = 1.0; KB = '1234' },
                [pscustomobject]@{ UpdateID = 'b'; Title = 'Update B'; SizeMb = 2.0; KB = '5678' }
            )

            Invoke-WindowsUpdates

            $script:InstallCalls.Count | Should Be 1
            $script:InstallCalls[0] | Should Be 2
            $script:Asked.Count | Should Be 1
        }

        It "scans again until no package is left" {
            $script:Packages = @(
                [pscustomobject]@{ UpdateID = 'a'; Title = 'Update A'; SizeMb = 1.0; KB = '1234' }
            )

            Invoke-WindowsUpdates

            # One install, then the next scan comes back empty.
            $script:SearchCalls | Should Be 2
            $script:InstallCalls.Count | Should Be 1
            $script:UpdateCheckResult.rounds | Should Be 2
            $script:UpdateCheckResult.upToDate | Should Be $true
            $script:UpdateCheckResult.installed | Should Be 1
        }

        It "stops when a reboot is required" {
            $script:Packages = @(
                [pscustomobject]@{ UpdateID = 'a'; Title = 'Update A'; SizeMb = 1.0; KB = '1234' }
            )
            $script:RebootRequired = $true

            Invoke-WindowsUpdates

            # The same packages would show up in the next scan, so the loop
            # ends here and the rest is picked up after the reboot.
            $script:SearchCalls | Should Be 1
            $script:InstallCalls.Count | Should Be 1
            $script:UpdateCheckResult.rebootRequired | Should Be $true
        }

        It "stops after the round cap" {
            $script:Packages = @(
                [pscustomobject]@{ UpdateID = 'a'; Title = 'Update A'; SizeMb = 1.0; KB = '1234' }
            )
            $script:PackagesRepeat = $true

            Invoke-WindowsUpdates

            $script:SearchCalls | Should Be $Config.UpdateMaxRounds
            $script:UpdateCheckResult.rounds | Should Be $Config.UpdateMaxRounds
        }

        It "stops when a round installs nothing" {
            $script:Packages = @(
                [pscustomobject]@{ UpdateID = 'a'; Title = 'Update A'; SizeMb = 1.0; KB = '1234' }
            )
            $script:InstallOk = $false

            Invoke-WindowsUpdates

            $script:SearchCalls | Should Be 1
            $script:InstallCalls.Count | Should Be 1
            $script:UpdateCheckResult.installed | Should Be 0
            $script:UpdateCheckResult.failed | Should Be 1
            $script:UpdateCheckResult.upToDate | Should Be $false
        }

        It "does not install when the user declines" {
            $script:Packages = @(
                [pscustomobject]@{ UpdateID = 'a'; Title = 'Update A'; SizeMb = 1.0; KB = '1234' }
            )
            $script:AnswerQueue.Enqueue($false)

            Invoke-WindowsUpdates

            $script:InstallCalls.Count | Should Be 0
            $script:UpdateCheckResult.installed | Should Be 0
        }

        It "opens the Windows Update page when the install is declined" {
            $script:Unattended = $false
            $script:Packages = @(
                [pscustomobject]@{ UpdateID = 'a'; Title = 'Update A'; SizeMb = 1.0; KB = '1234' }
            )
            $script:AnswerQueue.Enqueue($false)

            Invoke-WindowsUpdates

            $script:Started.Count | Should Be 1
            $script:Started[0] | Should Match 'windowsupdate'
        }

        It "never reboots the machine" {
            $script:Packages = @(
                [pscustomobject]@{ UpdateID = 'a'; Title = 'Update A'; SizeMb = 1.0; KB = '1234' }
            )

            Invoke-WindowsUpdates

            Assert-MockCalled Restart-Computer -Times 0 -Exactly -Scope It
        }

        It "continues when the scan fails" {
            Mock -CommandName Search-WindowsUpdates -MockWith { throw 'scan failed' }

            { Invoke-WindowsUpdates } | Should Not Throw

            $script:InstallCalls.Count | Should Be 0
            $script:UpdateCheckResult.upToDate | Should Be $false
        }

        It "skips the stage when -SkipUpdateCheck is passed" {
            $script:SkipUpdateCheck = $true

            Invoke-WindowsUpdates

            $script:SearchCalls | Should Be 0
            $script:UpdateCheckResult.skipped | Should Be $true
        }

        It "never touches PSWindowsUpdate, a package provider or a repository" {
            # Declared so the assertions below can prove none of them ran.
            Mock -CommandName Get-WindowsUpdate -MockWith { }
            Mock -CommandName Install-Module -MockWith { }
            Mock -CommandName Install-PackageProvider -MockWith { }
            Mock -CommandName Set-PSRepository -MockWith { }

            Invoke-WindowsUpdates

            # The install runs through the Windows Update client API, not
            # through a module from PSGallery.
            Assert-MockCalled Get-WindowsUpdate -Times 0 -Exactly -Scope It
            Assert-MockCalled Install-Module -Times 0 -Exactly -Scope It
            Assert-MockCalled Install-PackageProvider -Times 0 -Exactly -Scope It
            Assert-MockCalled Set-PSRepository -Times 0 -Exactly -Scope It
        }

        It "records the result in the state file" {
            $script:Packages = @(
                [pscustomobject]@{ UpdateID = 'a'; Title = 'Update A'; SizeMb = 1.0; KB = '1234' }
            )
            Mock -CommandName Test-ProfileLinked -MockWith { $true }

            Invoke-WindowsUpdates
            Complete-Bootstrap

            Test-Path $Config.StateFile | Should Be $true
            $state = Get-Content $Config.StateFile -Raw | ConvertFrom-Json
            $state.windowsUpdate.upToDate | Should Be $true
            $state.windowsUpdate.rounds | Should Be 2
            $state.windowsUpdate.installed | Should Be 1
            $state.windowsUpdate.rebootRequired | Should Be $false
            # The per-update detail is not stored: only the keys that are read.
            ($state.windowsUpdate.PSObject.Properties.Name -contains 'results') | Should Be $false
        }
    }


    Context "Get-UpdateSummary" {
        It "reports the size in MB" {
            $summary = Get-UpdateSummary -Update ([pscustomobject]@{
                UpdateID = 'a'; Title = 'Update A'; KBArticleIDs = @('1234'); MaxDownloadSize = 1048576
            })

            $summary.SizeMb | Should Be 1
            $summary.KB | Should Be '1234'
        }

        It "reports no size when the client does not know one" {
            $summary = Get-UpdateSummary -Update ([pscustomobject]@{
                UpdateID = 'a'; Title = 'Update A'; KBArticleIDs = @(); MaxDownloadSize = 0
            })

            $summary.SizeMb | Should BeNullOrEmpty
        }

        It "masks the junk the COM binder carries in the upper bits" {
            $summary = Get-UpdateSummary -Update ([pscustomobject]@{
                UpdateID = 'a'; Title = 'Update A'; KBArticleIDs = @(); MaxDownloadSize = 4294967296 + 1048576
            })

            $summary.SizeMb | Should Be 1
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
            # The gate: the Defender check verifies the Windows Security
            # toggles before the playbook runs.
            Mock -CommandName Invoke-DefenderCheck -MockWith { $true }
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
            # The CLI downloads the CLI archive and the playbook itself.
            $script:Downloads.Count | Should Be 2
            $script:Processes.Count | Should Be 1
            $script:Processes[0].FilePath | Should Match 'TrustedUninstaller\.CLI\.exe'
            ($script:Processes[0].ArgumentList | Measure-Object).Count | Should Be 16
            ($script:Processes[0].ArgumentList -contains 'browser-brave') | Should Be $false
            ($script:Processes[0].ArgumentList -contains 'remove-edge') | Should Be $false
            $script:Asked.Count | Should Be 1
            # The Defender check runs before the playbook.
            Assert-MockCalled Invoke-DefenderCheck -Times 1 -Exactly -Scope It
            Test-Path $script:Marker | Should Be $true
        }

        It "declining confirmation warns and continues (no throw)" {
            $script:AnswerQueue.Enqueue($false)
            { Invoke-Debloat } | Should Not Throw
            $script:Processes.Count | Should Be 0
            Test-Path $script:Marker | Should Be $false
        }

        It "missing artifacts throws" {
            # The CLI verifies the downloads itself and refuses to apply.
            $script:ArtifactOk = $false
            { Invoke-Debloat } | Should Throw
        }

        It "blocks before the CLI when the Defender toggles stay on" {
            Mock -CommandName Invoke-DefenderCheck -MockWith { $false }
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
            $script:ProfilePath = ''

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
            Mock -CommandName Assert-Administrator -MockWith { $script:Order.Add('Assert-Administrator') }
            Mock -CommandName Initialize-Environment -MockWith { $script:Order.Add('Initialize-Environment') }
            Mock -CommandName Initialize-Scoop -MockWith { $script:Order.Add('Initialize-Scoop') }
            Mock -CommandName Initialize-Winget -MockWith { $script:Order.Add('Initialize-Winget') }
            Mock -CommandName Invoke-WindowsUpdates -MockWith { $script:Order.Add('Invoke-WindowsUpdates') }
            Mock -CommandName Invoke-Debloat -MockWith { $script:Order.Add('Invoke-Debloat') }
            Mock -CommandName Invoke-Drivers -MockWith { $script:Order.Add('Invoke-Drivers') }
            Mock -CommandName Complete-Bootstrap -MockWith { $script:Order.Add('Complete-Bootstrap') }
        }

        It "runs every stage in order" {
            main

            ($script:Order -join '>') | Should Be 'Assert-Administrator>Invoke-WindowsUpdates>Initialize-Environment>Initialize-Scoop>Initialize-Winget>Invoke-Debloat>Invoke-Drivers>Complete-Bootstrap'
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
