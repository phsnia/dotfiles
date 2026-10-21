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
            'Confirm-DefenderStep'
            'Get-DefenderTogglesOn'
            'Set-TamperProtectionOff'
            'Set-DefenderPolicy'
            'Show-DefenderSettings'
            'Disable-Defender'
            'Test-DefenderOff'
            'Resolve-DefenderManually'
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
            Get-Command Confirm-DefenderStep -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Get-DefenderTogglesOn -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Set-TamperProtectionOff -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Set-DefenderPolicy -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Show-DefenderSettings -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Disable-Defender -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Test-DefenderOff -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Resolve-DefenderManually -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
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

    Context "Set-TamperProtectionOff" {
        BeforeEach {
            Mock -CommandName Test-Path -MockWith { $false }
            Mock -CommandName New-Item -MockWith { $script:PathCreates.Add("$Path") }
            Mock -CommandName Set-ItemProperty -MockWith {
                $script:RegistryWrites.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value })
            }
        }

        It "switches Tamper Protection off through the module" {
            Mock -CommandName Set-MpPreference -MockWith {
                $script:MpPreferenceCalls.Add([pscustomobject]@{ DisableTamperProtection = $DisableTamperProtection })
            }

            $ok = Set-TamperProtectionOff

            $ok | Should Be $true
            $script:MpPreferenceCalls.Count | Should Be 1
            $script:MpPreferenceCalls[0].DisableTamperProtection | Should Be $true
            $script:RegistryWrites.Count | Should Be 0
        }

        It "falls back to the registry when the module refuses" {
            Mock -CommandName Set-MpPreference -MockWith { throw '0x80004001' }

            $ok = Set-TamperProtectionOff

            $ok | Should Be $true
            $write = $script:RegistryWrites | Where-Object { $_.Name -eq 'TamperProtection' } | Select-Object -First 1
            $write | Should Not BeNullOrEmpty
            $write.Value | Should Be 0
        }

        It "reports a refused write instead of throwing" {
            Mock -CommandName Set-MpPreference -MockWith { throw '0x80004001' }
            Mock -CommandName Set-ItemProperty -MockWith { throw 'key is protected' }

            $ok = Set-TamperProtectionOff

            $ok | Should Be $false
        }
    }

    Context "Disable-Defender" {
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
            Mock -CommandName Set-ItemProperty -MockWith {
                $script:RegistryWrites.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value })
            }
            Mock -CommandName New-Item -MockWith { $script:PathCreates.Add("$Path") }
            Mock -CommandName Test-Path -MockWith { $true }
            Mock -CommandName Confirm-DefenderStep -MockWith {
                param($Question)
                $script:Asked.Add($Question)
                if ($script:AnswerQueue.Count -gt 0) { [bool]$script:AnswerQueue.Dequeue() } else { $true }
            }
            Mock -CommandName Set-MpPreference -MockWith {
                $script:MpPreferenceCalls.Add([pscustomobject]@{
                    DisableRealtimeMonitoring = $DisableRealtimeMonitoring
                    DisableBehaviorMonitoring = $DisableBehaviorMonitoring
                    DisableIOAVProtection     = $DisableIOAVProtection
                    DisableBlockAtFirstSeen  = $DisableBlockAtFirstSeen
                    MAPSReporting             = "$MAPSReporting"
                    SubmitSamplesConsent      = "$SubmitSamplesConsent"
                    DisableTamperProtection   = [bool]$DisableTamperProtection
                })
            }
        }

        It "skips when every toggle is already off" {
            $script:RealTime = $false
            $script:TamperDisabled = $true
            $script:MapsReporting = 0
            $script:SubmitSamplesConsent = 2
            $script:DisableBlockAtFirstSeen = $true

            Disable-Defender

            $script:MpPreferenceCalls.Count | Should Be 0
            $script:RegistryWrites.Count | Should Be 0
        }

        It "turns off every protection on the checklist" {
            Disable-Defender

            # The tamper switch is a separate call - look at the preferences one.
            $preferences = @($script:MpPreferenceCalls | Where-Object { -not $_.DisableTamperProtection })
            $preferences.Count | Should Be 1
            $call = $preferences[0]
            $call.DisableRealtimeMonitoring | Should Be $true
            $call.DisableBehaviorMonitoring | Should Be $true
            $call.DisableIOAVProtection | Should Be $true
            $call.DisableBlockAtFirstSeen | Should Be $true
            $call.MAPSReporting | Should Be 'Disabled'
            $call.SubmitSamplesConsent | Should Be 'NeverSend'
        }

        It "writes the DisableAntiSpyware policy" {
            Disable-Defender

            $write = $script:RegistryWrites | Where-Object { $_.Name -eq 'DisableAntiSpyware' } | Select-Object -First 1
            $write | Should Not BeNullOrEmpty
            $write.Value | Should Be 1
        }

        It "tries to release Tamper Protection before the preference writes" {
            Disable-Defender

            $tamperCalls = @($script:MpPreferenceCalls | Where-Object { $_.DisableTamperProtection })
            $tamperCalls.Count | Should Be 1
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

    Context "Resolve-DefenderManually" {
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
            Mock -CommandName Confirm-DefenderStep -MockWith {
                param($Question)
                $script:Asked.Add($Question)
                if ($script:AnswerQueue.Count -gt 0) { [bool]$script:AnswerQueue.Dequeue() } else { $true }
            }
        }

        It "does nothing when every toggle is off" {
            $script:RealTime = $false
            $script:TamperDisabled = $true
            $script:MapsReporting = 0
            $script:SubmitSamplesConsent = 2
            $script:DisableBlockAtFirstSeen = $true

            $ok = Resolve-DefenderManually

            $ok | Should Be $true
            $script:SettingsShown | Should Be 0
            $script:Asked.Count | Should Be 0
        }

        It "opens Windows Security and waits for the user" {
            $ok = Resolve-DefenderManually

            $script:SettingsShown | Should BeGreaterThan 0
            $script:Asked.Count | Should BeGreaterThan 0
            $script:Asked[0] | Should Match 'Windows Security'
            $ok | Should Be $false
        }

        It "returns true as soon as the toggles are off" {
            Mock -CommandName Confirm-DefenderStep -MockWith {
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

            $ok = Resolve-DefenderManually

            $ok | Should Be $true
            $script:SettingsShown | Should Be 1
        }
    }
}
