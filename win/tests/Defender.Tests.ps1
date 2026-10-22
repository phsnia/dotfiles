# Defender.Tests.ps1 - Pester tests for the Windows Defender check
#
# The check lives in win/bootstrap.ps1 - the Defender stage that gates the
# debloat. The Defender cmdlets and the registry are mocked, so nothing on
# the host is touched: the tests only prove the code reads the state, hands
# the toggles to the user and verifies the result.

Describe "windows defender (Pester)" {
    BeforeAll {
        $testsRoot   = Split-Path $PSCommandPath -Parent
        $winRoot     = Split-Path $testsRoot -Parent
        $bootstrapPs = Join-Path $winRoot 'bootstrap.ps1'

        # The Defender helpers live in bootstrap.ps1 - load them via AST
        # (skips the entry point).
        $defenderFunctions = @(
            'Get-DefenderTogglesOn'
            'Invoke-DefenderCheck'
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

        # Defender state the mocked cmdlets report.
        $script:RealTime = $true
        $script:TamperDisabled = $false   # $false = Tamper Protection is on
        $script:MapsReporting = 2          # 2 = cloud protection on
        $script:SubmitSamplesConsent = 2   # 2 = always send samples
        # "Block at first sight" is a hidden preference, not a toggle of the
        # UI: it stays at its default no matter what the user switches off.
        $script:DisableBlockAtFirstSeen = $false

        # Recorded calls.
        $script:MpPreferenceCalls = [System.Collections.Generic.List[object]]::new()
        $script:RegistryWrites = [System.Collections.Generic.List[object]]::new()
        $script:PathCreates = [System.Collections.Generic.List[string]]::new()
    }

    Context "Parsing and loading" {
        It "loads the functions from bootstrap.ps1" {
            Get-Command Get-DefenderTogglesOn -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            Get-Command Invoke-DefenderCheck -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            # The stage is manual now: nothing scripted is left behind.
            Get-Command Set-TamperProtectionOff -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Set-DefenderPolicy -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Resolve-DefenderManually -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            # The old stage helper is gone: the simple check replaced it.
            Get-Command Disable-Defender -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            # The one-caller helpers were merged into the check.
            Get-Command Show-DefenderSettings -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            Get-Command Test-DefenderOff -ErrorAction SilentlyContinue | Should BeNullOrEmpty
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
            $script:SubmitSamplesConsent = 0
            # "Block at first sight" keeps its default - the UI toggle does
            # not touch it.
            $script:DisableBlockAtFirstSeen = $false

            @(Get-DefenderTogglesOn).Count | Should Be 0
        }

        It "reads the sample submission toggle as off when it never sends" {
            $script:RealTime = $false
            $script:TamperDisabled = $true
            $script:MapsReporting = 0
            $script:SubmitSamplesConsent = 0

            $on = @(Get-DefenderTogglesOn)

            ($on -contains 'Automatic sample submission') | Should Be $false
        }

        It "ignores the hidden block-at-first-sight preference" {
            $script:RealTime = $false
            $script:TamperDisabled = $true
            $script:MapsReporting = 0
            $script:SubmitSamplesConsent = 0
            $script:DisableBlockAtFirstSeen = $false

            $on = @(Get-DefenderTogglesOn)

            # It is not a toggle of the Windows Security UI, so it must not
            # keep the stage in its hand-over loop.
            ($on -contains 'Cloud-delivered protection') | Should Be $false
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

        It "counts Tamper protection as on when it cannot be read" {
            Mock -CommandName Get-MpPreference -MockWith {
                [pscustomobject]@{
                    DisableBlockAtFirstSeen = $script:DisableBlockAtFirstSeen
                    MAPSReporting           = $script:MapsReporting
                    SubmitSamplesConsent    = $script:SubmitSamplesConsent
                    DisableTamperProtection = $null
                }
            }
            Mock -CommandName Get-ItemProperty -MockWith { $null }

            $on = @(Get-DefenderTogglesOn)

            # Unknown counts as on: the playbook refuses a protected machine.
            ($on -contains 'Tamper protection') | Should Be $true
        }
    }

    Context "Invoke-DefenderCheck" {
        BeforeEach {
            $script:SettingsShown = 0
            $script:Started = [System.Collections.Generic.List[string]]::new()
            $script:Prompts = [System.Collections.Generic.List[string]]::new()
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
            # The check opens Windows Security itself.
            Mock -CommandName Start-Process -MockWith {
                $script:SettingsShown++
                $script:Started.Add("$FilePath")
            }
            # The script hands the toggles to the user and waits for Enter.
            Mock -CommandName Read-Host -MockWith {
                param($Prompt)
                $script:Prompts.Add("$Prompt")
                ''
            }
            # Declared so the tests can prove nothing is ever written.
            Mock -CommandName Set-MpPreference -MockWith { $script:MpPreferenceCalls.Add($null) }
            Mock -CommandName Set-ItemProperty -MockWith {
                $script:RegistryWrites.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value })
            }
            Mock -CommandName New-Item -MockWith { $script:PathCreates.Add("$Path") }
        }

        It "skips the hand-over when every toggle is already off" {
            $script:RealTime = $false
            $script:TamperDisabled = $true
            $script:MapsReporting = 0
            $script:SubmitSamplesConsent = 0
            $script:DisableBlockAtFirstSeen = $false

            $ok = Invoke-DefenderCheck

            $ok | Should Be $true
            $script:SettingsShown | Should Be 0
            $script:Prompts.Count | Should Be 0
        }

        It "opens Windows Security and waits for the user" {
            $ok = Invoke-DefenderCheck

            $script:SettingsShown | Should BeGreaterThan 0
            $script:Prompts.Count | Should BeGreaterThan 0
            $script:Prompts[0] | Should Match 'Enter'
            $ok | Should Be $false
        }

        It "returns true as soon as the toggles are off" {
            Mock -CommandName Read-Host -MockWith {
                param($Prompt)
                $script:Prompts.Add("$Prompt")
                # The user flips the toggles before the script checks again.
                $script:RealTime = $false
                $script:TamperDisabled = $true
                $script:MapsReporting = 0
                $script:SubmitSamplesConsent = 0
                $script:DisableBlockAtFirstSeen = $false
                ''
            }

            $ok = Invoke-DefenderCheck

            $ok | Should Be $true
            $script:SettingsShown | Should Be 1
        }

        It "reports only and does not wait in unattended mode" {
            $ok = Invoke-DefenderCheck -Unattended

            $ok | Should Be $false
            $script:SettingsShown | Should Be 0
            $script:Prompts.Count | Should Be 0
        }

        It "never writes to the platform" {
            Invoke-DefenderCheck

            # Manual only: no preference call, no policy keys, no folders.
            Assert-MockCalled Set-MpPreference -Times 0 -Exactly -Scope It
            Assert-MockCalled Set-ItemProperty -Times 0 -Exactly -Scope It
            Assert-MockCalled New-Item -Times 0 -Exactly -Scope It
        }
    }

    Context "Windows Security page" {
        BeforeEach {
            $script:Started = [System.Collections.Generic.List[string]]::new()
            $script:Prompts = [System.Collections.Generic.List[string]]::new()
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
            Mock -CommandName Read-Host -MockWith { param($Prompt) $script:Prompts.Add("$Prompt"); '' }
        }

        It "opens the Windows Security page" {
            Mock -CommandName Start-Process -MockWith { $script:Started.Add("$FilePath") }

            $null = Invoke-DefenderCheck

            $script:Started.Count | Should Be 1
            $script:Started[0] | Should Match 'windowsdefender'
        }

        It "falls back to the second page when the first cannot be opened" {
            Mock -CommandName Start-Process -MockWith {
                if ("$FilePath" -like 'ms-settings:*') { throw 'no such page' }
                $script:Started.Add("$FilePath")
            }

            $null = Invoke-DefenderCheck

            $script:Started.Count | Should Be 1
            $script:Started[0] | Should Match 'threatsettings'
        }
    }

}

