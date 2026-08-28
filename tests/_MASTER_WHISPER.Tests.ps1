Describe "Master Whisper Script Tests" {
    BeforeAll {
        $ScriptPath = Join-Path $PSScriptRoot "..\src\_MASTER_WHISPER.ps1"
        if (-not (Test-Path $ScriptPath)) {
            $ScriptPath = Join-Path $PSScriptRoot "..\_MASTER_WHISPER.ps1"
        }

        $ScriptContent = Get-Content -Path $ScriptPath -Raw -Encoding UTF8
        
        # Extract Get-MissingMdFiles function definition
        if ($ScriptContent -match '(?ms)(function Get-MissingMdFiles\s*\{.+?^\})') {
            Invoke-Expression $Matches[1]
        }
        
        # Extract Parse-FileNameParameters function definition
        if ($ScriptContent -match '(?ms)(function Parse-FileNameParameters\s*\{.+?^\})') {
            Invoke-Expression $Matches[1]
        }
    }

    Context "Filename Parameter Parsing (file.LL-X#.ext)" {
        It "Parses Slovak meeting with 3 speakers" {
            $result = Parse-FileNameParameters -FileName "project_discussion.SK-M3.mp3"
            $result.Language | Should Be "sk"
            $result.Profile | Should Be "meeting"
            $result.MinSpeakers | Should Be 3
            $result.MaxSpeakers | Should Be 3
        }

        It "Parses English phone call with 2 speakers" {
            $result = Parse-FileNameParameters -FileName "customer_call.EN-P2.m4a"
            $result.Language | Should Be "en"
            $result.Profile | Should Be "phone"
            $result.MinSpeakers | Should Be 2
            $result.MaxSpeakers | Should Be 2
        }

        It "Parses Czech distant recording with 4 speakers" {
            $result = Parse-FileNameParameters -FileName "conference_hall.CS-D4.flac"
            $result.Language | Should Be "cs"
            $result.Profile | Should Be "distant"
            $result.MinSpeakers | Should Be 4
            $result.MaxSpeakers | Should Be 4
        }

        It "Returns default phone profile and empty auto-detect language for untagged files" {
            $result = Parse-FileNameParameters -FileName "standard_voice_memo.m4a"
            $result.Language | Should Be ""
            $result.Profile | Should Be "phone"
            $result.MinSpeakers | Should Be 2
            $result.MaxSpeakers | Should Be 2
        }
    }

    Context "Missing Markdown Files Detection" {
        BeforeEach {
            $TestDir = Join-Path $env:TEMP "pester_md_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $TestDir -Force | Out-Null
            $TestBase = Join-Path $TestDir "recording1"
        }

        AfterEach {
            if ($TestDir -and (Test-Path $TestDir)) {
                Remove-Item -Path $TestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Detects mode 'both' when neither NOTES.md nor SUMMARY.md exist" {
            $check = Get-MissingMdFiles -BasePath $TestBase
            $check.NotesMissing | Should Be $true
            $check.SummaryMissing | Should Be $true
            $check.GenerateMode | Should Be "both"
        }

        It "Detects mode 'summary' when only NOTES.md exists" {
            Set-Content -Path "$TestBase.NOTES.md" -Value "# Notes" -Encoding UTF8
            $check = Get-MissingMdFiles -BasePath $TestBase
            $check.NotesMissing | Should Be $false
            $check.SummaryMissing | Should Be $true
            $check.GenerateMode | Should Be "summary"
        }

        It "Detects mode 'notes' when only SUMMARY.md exists" {
            Set-Content -Path "$TestBase.SUMMARY.md" -Value "# Summary" -Encoding UTF8
            $check = Get-MissingMdFiles -BasePath $TestBase
            $check.NotesMissing | Should Be $true
            $check.SummaryMissing | Should Be $false
            $check.GenerateMode | Should Be "notes"
        }

        It "Detects mode 'none' when both MD files exist" {
            Set-Content -Path "$TestBase.NOTES.md" -Value "# Notes" -Encoding UTF8
            Set-Content -Path "$TestBase.SUMMARY.md" -Value "# Summary" -Encoding UTF8
            $check = Get-MissingMdFiles -BasePath $TestBase
            $check.NotesMissing | Should Be $false
            $check.SummaryMissing | Should Be $false
            $check.GenerateMode | Should Be "none"
        }
    }
}
