# Defender.Tests.ps1 - Pester tests for the Windows Defender stage
#
# The Defender cmdlets and the registry are mocked, so nothing on the
# host is touched: the tests only prove the code reads the state, asks
# for what it needs and verifies the result.

Describe "windows defender (Pester)" {
    BeforeAll {
        $testsRoot   = Split-Path $PSCommandPath -Parent
        $winRoot     = Split-Path $testsRoot -Parent
        $bootstrapPs = Join-Path $winRoot 'bootstrap.ps1'

        # The Defender helpers live in bootstrap.ps1 - load them via AST
        # (skips the entry point).
        $defenderFunctions = @(
            'Confirm-Step'
            'Get-DefenderTogglesOn'
            'Show-DefenderSettings'
            'Disable-Defender'
            'Test-DefenderOff'
        )

        $tokens = $null; $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($bootstrapPs, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors) { throw "Parse errors in bootstrap.ps1: $parseErrors" }
        $functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) |
            Where-Object { $defenderFunctions -contains $_.Name }
        if ($functions.Count -ne $defenderFunctions.Count) {
            throw "Defender functions missing in bootstrap.ps1: found $($functions.Count) of $($defenderFunctions.Count)"
        }
        foreach ($fn in $functions) { Invoke-Expression $fn.Extent.Text }

        # Pester builds its mock proxy from the parameters of the mocked
        # command, and the Defender module does not expose
        # -DisableTamperProtection on every build. A stub keeps the
        # "never writes" assertion host-independent.
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
        $script:Unattended = $true

        # Shared prompt state
        $script:Asked = [System.Collections.Generic.List[string]]::new()
        $script:AnswerQueue = [System.Collections.Generic.Queue[bool]]::new()

        # Defender state the mocked cmdlets report.
        $script:RealTime = $true
        $script:TamperDisabled = $false   # $false = Tamper Protection is on
        $script:MapsReporting = 2
        $script:SubmitSamplesConsent = 1
        $script:DisableBlockAtFirstSeen = $true

        # Recorded calls.
        $script:MpPreferenceCalls = [System.Collections.Generic.List[object]]::new()
        $script:RegistryWrites = [System.Collections.Generic.List[object]]::new()
        $script:PathCreates = [System.Collections.Generic.List[string]]::new()
    }

    Context "Parsing and loading" {
        It "loads the functions from bootstrap.ps1" {
            Get-Command Get-DefenderTogglesOn -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Show-DefenderSettings -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Disable-Defender -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Test-DefenderOff -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            # The stage is manual now: nothing scripted is left behind.
            Get-Command Set-TamperProtectionOff -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Set-DefenderPolicy -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Resolve-DefenderManually -ErrorAction SilentlyContinue | Should BeNullOrEmpty
        }
    }

    Context "Get-DefenderTogglesOn" {
        BeforeEach {
            Mock -CommandName Get-MpComputerStatus -MockWith {
                [pscustomobject]@{ RealTimeProtectionEnabled = $script:RealTime }
            }
            Mock -CommandName Get-MpPreference -MockWith {
                [pscustomobject]@{
                    DisableBlockAtFirstSeen = $script:DisableBlockAtFirstSeen
                    MAPSReporting           = $script:MapsReporting
                    SubmitSamplesConsent    = $script:SubmitSamplesConsent
                    DisableTamperProtection = $script:TamperDisabled
                }
            }
            Mock -CommandName Get-ItemProperty -MockWith {
                [pscustomobject]@{ TamperProtection = [int](-not $script:TamperDisabled) }
            }
        }

        It "lists the four toggles that are still on" {
            $on = @(Get-DefenderTogglesOn)

            ($on -contains 'Real-time protection') | Should Be $true
            ($on -contains 'Cloud-delivered protection') | Should Be $true
            ($on -contains 'Automatic sample submission') | Should Be $true
            ($on -contains 'Tamper protection') | Should Be $true
            $on.Count | Should Be 4
        }

        It "returns nothing when every toggle is off" {
            $script:RealTime = $false
            $script:TamperDisabled = $true
            $script:MapsReporting = 0
            $script:SubmitSamplesConsent = 2
            # DisableBlockAtFirstSeen = $true means the block is off.
            $script:DisableBlockAtFirstSeen = $true

            @(Get-DefenderTogglesOn).Count | Should Be 0
        }

        It "falls back to the registry when the module has no tamper preference" {
            Mock -CommandName Get-MpPreference -MockWith {
                [pscustomobject]@{
                    DisableBlockAtFirstSeen = $script:DisableBlockAtFirstSeen
                    MAPSReporting           = $script:MapsReporting
                    SubmitSamplesConsent    = $script:SubmitSamplesConsent
                    DisableTamperProtection = $null
                }
            }

            $on = @(Get-DefenderTogglesOn)

            ($on -contains 'Tamper protection') | Should Be $true
        }
    }

    Context "Disable-Defender" {
        BeforeEach {
            $script:SettingsShown = 0
            Mock -CommandName Get-MpComputerStatus -MockWith {
                [pscustomobject]@{ RealTimeProtectionEnabled = $script:RealTime }
            }
            Mock -CommandName Get-MpPreference -MockWith {
                [pscustomobject]@{
                    DisableBlockAtFirstSeen = $script:DisableBlockAtFirstSeen
                    MAPSReporting           = $script:MapsReporting
                    SubmitSamplesConsent    = $script:SubmitSamplesConsent
                    DisableTamperProtection = $script:TamperDisabled
                }
            }
            Mock -CommandName Get-ItemProperty -MockWith {
                [pscustomobject]@{ TamperProtection = [int](-not $script:TamperDisabled) }
            }
            Mock -CommandName Show-DefenderSettings -MockWith { $script:SettingsShown++ }
            Mock -CommandName Confirm-Step -MockWith {
                param($Question)
                $script:Asked.Add($Question)
                if ($script:AnswerQueue.Count -gt 0) { [bool]$script:AnswerQueue.Dequeue() } else { $true }
            }
            # Declared so the tests can prove nothing is ever written.
            Mock -CommandName Set-MpPreference -MockWith { $script:MpPreferenceCalls.Add($null) }
            Mock -CommandName Set-ItemProperty -MockWith {
                $script:RegistryWrites.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value })
            }
            Mock -CommandName New-Item -MockWith { $script:PathCreates.Add("$Path") }
        }

        It "skips when every toggle is already off" {
            $script:RealTime = $false
            $script:TamperDisabled = $true
            $script:MapsReporting = 0
            $script:SubmitSamplesConsent = 2
            $script:DisableBlockAtFirstSeen = $true

            $ok = Disable-Defender

            $ok | Should Be $true
            $script:SettingsShown | Should Be 0
            $script:Asked.Count | Should Be 0
        }

        It "opens Windows Security and waits for the user" {
            $ok = Disable-Defender

            $script:SettingsShown | Should BeGreaterThan 0
            $script:Asked.Count | Should BeGreaterThan 0
            $script:Asked[0] | Should Match 'Windows Security'
            $ok | Should Be $false
        }

        It "returns true as soon as the toggles are off" {
            Mock -CommandName Confirm-Step -MockWith {
                param($Question)
                $script:Asked.Add($Question)
                # The user flips the toggles before the script checks again.
                $script:RealTime = $false
                $script:TamperDisabled = $true
                $script:MapsReporting = 0
                $script:SubmitSamplesConsent = 2
                $script:DisableBlockAtFirstSeen = $true
                $true
            }

            $ok = Disable-Defender

            $ok | Should Be $true
            $script:SettingsShown | Should Be 1
        }

        It "never writes to the platform" {
            Disable-Defender

            # Manual only: no preference call, no policy keys, no folders.
            Assert-MockCalled Set-MpPreference -Times 0 -Exactly -Scope It
            Assert-MockCalled Set-ItemProperty -Times 0 -Exactly -Scope It
            Assert-MockCalled New-Item -Times 0 -Exactly -Scope It
        }
    }

    Context "Show-DefenderSettings" {
        BeforeEach {
            $script:Started = [System.Collections.Generic.List[string]]::new()
        }

        It "opens the Windows Security page" {
            Mock -CommandName Start-Process -MockWith { $script:Started.Add("$FilePath") }

            $ok = Show-DefenderSettings

            $ok | Should Be $true
            $script:Started.Count | Should Be 1
            $script:Started[0] | Should Match 'windowsdefender'
        }

        It "falls back to the second page when the first cannot be opened" {
            Mock -CommandName Start-Process -MockWith {
                if ("$FilePath" -like 'ms-settings:*') { throw 'no such page' }
                $script:Started.Add("$FilePath")
            }

            $ok = Show-DefenderSettings

            $ok | Should Be $true
            $script:Started.Count | Should Be 1
            $script:Started[0] | Should Match 'threatsettings'
        }
    }

}

