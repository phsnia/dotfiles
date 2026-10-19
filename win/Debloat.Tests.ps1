# Debloat.Tests.ps1 - Pester tests for the debloat flow

Describe "Bootstrap debloat (Pester)" {
    BeforeAll {
        $scriptRoot = Split-Path $PSCommandPath -Parent
        $bootstrap = Join-Path $scriptRoot 'bootstrap.ps1'
        $ameCli    = Join-Path $scriptRoot 'ame-cli.ps1'

        # Load functions via AST (skip main)
        $tokens = $null; $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($bootstrap, [ref]$tokens, [ref]$parseErrors) | Out-Null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($bootstrap, [ref]$tokens, [ref]$parseErrors)
        $functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
        foreach ($fn in $functions) { Invoke-Expression $fn.Extent.Text }
        . $ameCli

        # Real-like config for tests
        $script:Config = @{
            Downloads     = $env:TEMP
            StateDir      = $env:TEMP
            LogFile       = Join-Path $env:TEMP 'test-bootstrap.log'
            StateFile     = Join-Path $env:TEMP 'test-bootstrap.state.json'
            ReviPlaybook  = 'https://example.invalid/Revi-PB.apbx'
            CliStandalone = 'https://example.invalid/CLI-Standalone.zip'
        }

        # State
        $script:Asked = [System.Collections.Generic.List[string]]::new()
        $script:AnswerQueue = [System.Collections.Generic.Queue[bool]]::new()
        $script:Logged = [System.Collections.Generic.List[object]]::new()
        $script:Processes = [System.Collections.Generic.List[object]]::new()
        $script:Downloads = [System.Collections.Generic.List[string]]::new()
        $script:Markers = [System.Collections.Generic.List[string]]::new()
        $script:ArchiveRuns = 0
        $script:SevenZipRuns = 0
        $script:DefenderCalls = 0
        $script:PolicyWrites = 0
        $script:RealTimeProtection = $false
        $script:ArtifactOk = $true
        $script:StageMarkerExists = $false
        $script:Extracted = @{ Cli = $false; Playbook = $false }
    }
    BeforeEach {
        $script:Asked.Clear()
        $script:AnswerQueue.Clear()
        $script:Logged.Clear()
        $script:Processes.Clear()
        $script:Downloads.Clear()
        $script:Markers.Clear()
        $script:ArchiveRuns = 0
        $script:SevenZipRuns = 0
        $script:DefenderCalls = 0
        $script:PolicyWrites = 0
        $script:RealTimeProtection = $false
        $script:ArtifactOk = $true
        $script:StageMarkerExists = $false
        $script:Extracted = @{ Cli = $false; Playbook = $false }
    }

    Context "Parsing and loading" {
        It "loads functions from bootstrap.ps1" {
            Get-Command Invoke-Debloat -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Disable-Defender -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Invoke-ReviCli -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
    }

    Context "Mocks" {
        BeforeEach {
            Mock -CommandName Write-Log -MockWith { param($Message,$Level='INFO') $script:Logged.Add(@{Message=$Message; Level=$Level}) }
            Mock -CommandName Get-RemoteFile -MockWith { param($Url,$Directory) $script:Downloads.Add($Url); Join-Path $Directory (Split-Path $Url -Leaf) }
            Mock -CommandName Test-Artifact -MockWith { $script:ArtifactOk }
            Mock -CommandName Confirm-Step -MockWith { param($Question) $script:Asked.Add($Question); if ($script:AnswerQueue.Count -gt 0) { [bool]$script:AnswerQueue.Dequeue() } else { $true } }
            Mock -CommandName Set-MpPreference -MockWith { $script:DefenderCalls++ }
            Mock -CommandName Get-MpComputerStatus -MockWith { [pscustomobject]@{ RealTimeProtectionEnabled = $script:RealTimeProtection } }
            Mock -CommandName Test-Path -MockWith {
                param($Path)
                if ($script:StageMarkerExists -and "$Path" -like '*stage-debloat.done') { return $true }
                return $false
            }
            Mock -CommandName New-Item -MockWith {}
            Mock -CommandName Set-ItemProperty -MockWith { $script:PolicyWrites++ }
            Mock -CommandName Set-Content -MockWith { param($Path) if ("$Path" -like '*stage-*.done') { $script:Markers.Add($Path) } }
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
            $script:Markers.Count | Should Be 1
        }

        It "declining confirmation warns and continues (no throw)" {
            $script:AnswerQueue.Enqueue($false)
            { Invoke-Debloat } | Should Not Throw
            $script:Processes.Count | Should Be 0
            $script:Markers.Count | Should Be 0
        }

        It "missing artifacts throws" {
            $script:ArtifactOk = $false
            { Invoke-Debloat } | Should Throw
        }

        It "stage marker skips entirely" {
            $script:StageMarkerExists = $true
            { Invoke-Debloat } | Should Not Throw
            $script:Downloads.Count | Should Be 0
            $script:Processes.Count | Should Be 0
        }
    }

    AfterAll {
        # Keep the console open after the checks when launched interactively
        # (same 'Press Enter to exit' behavior as bootstrap.ps1). Skipped in
        # non-interactive hosts and CI so automated runs don't hang.
        $isCi = $env:CI -or $env:AGENT_ID -or $env:GITHUB_ACTIONS -or $env:TF_BUILD
        if ([Environment]::UserInteractive -and -not $isCi) {
            Write-Host 'Press Enter to exit' -NoNewline
            $null = Read-Host
        }
    }
}