Describe "Master Whisper Script Tests" {
    BeforeAll {
        $ScriptPath = Join-Path $PSScriptRoot "..\src\_MASTER_WHISPER.ps1"
        if (-not (Test-Path $ScriptPath)) {
            $ScriptPath = Join-Path $PSScriptRoot "..\_MASTER_WHISPER.ps1"
        }

        $ScriptContent = Get-Content -Path $ScriptPath -Raw -Encoding UTF8
        
        # Extract Get-MissingMdFiles function definition and inject into global scope
        if ($ScriptContent -match '(?ms)function Get-MissingMdFiles\s*\{(.+?^\})') {
            $fnBody = "function global:Get-MissingMdFiles { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }
        
        # Extract Parse-FileNameParameters function definition and inject into global scope
        if ($ScriptContent -match '(?ms)function Parse-FileNameParameters\s*\{(.+?^\})') {
            $fnBody = "function global:Parse-FileNameParameters { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }

        # Extract Get-DjiScriptPath function definition and inject into global scope
        if ($ScriptContent -match '(?ms)function Get-DjiScriptPath\s*\{(.+?^\})') {
            $fnBody = "function global:Get-DjiScriptPath { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }

        # Extract Invoke-DjiConversion function definition and inject into global scope
        if ($ScriptContent -match '(?ms)function Invoke-DjiConversion\s*\{(.+?^\})') {
            $fnBody = "function global:Invoke-DjiConversion { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }
    }

    Context "Filename Parameter Parsing (file.LL-X#.ext)" {
        It "Parses Slovak meeting with 3 speakers" {
            $result = Parse-FileNameParameters -FileName "project_discussion.SK-M3.mp3"
            $result.Language | Should -Be "sk"
            $result.Profile | Should -Be "meeting"
            $result.MinSpeakers | Should -Be 3
            $result.MaxSpeakers | Should -Be 3
        }

        It "Parses English phone call with 2 speakers" {
            $result = Parse-FileNameParameters -FileName "customer_call.EN-P2.m4a"
            $result.Language | Should -Be "en"
            $result.Profile | Should -Be "phone"
            $result.MinSpeakers | Should -Be 2
            $result.MaxSpeakers | Should -Be 2
        }

        It "Parses Czech distant recording with 4 speakers" {
            $result = Parse-FileNameParameters -FileName "conference_hall.CS-D4.flac"
            $result.Language | Should -Be "cs"
            $result.Profile | Should -Be "distant"
            $result.MinSpeakers | Should -Be 4
            $result.MaxSpeakers | Should -Be 4
        }

        It "Parses Slovak hallway recording with 2 speakers" {
            $result = Parse-FileNameParameters -FileName "corridor_cam.SK-H2.mp4"
            $result.Language | Should -Be "sk"
            $result.Profile | Should -Be "hallway"
            $result.MinSpeakers | Should -Be 2
            $result.MaxSpeakers | Should -Be 2
        }

        It "Parses Slovak echoed recording with 2 speakers" {
            $result = Parse-FileNameParameters -FileName "echo_hall.SK-E2.mp4"
            $result.Language | Should -Be "sk"
            $result.Profile | Should -Be "echoed"
            $result.MinSpeakers | Should -Be 2
            $result.MaxSpeakers | Should -Be 2
        }

        It "Returns default phone profile and empty auto-detect language for untagged files" {
            $result = Parse-FileNameParameters -FileName "standard_voice_memo.m4a"
            $result.Language | Should -Be ""
            $result.Profile | Should -Be "phone"
            $result.MinSpeakers | Should -Be 2
            $result.MaxSpeakers | Should -Be 2
            $result.IsDefault | Should -BeTrue
        }

        It "Marks tagged files with IsDefault as false" {
            $result = Parse-FileNameParameters -FileName "customer_call.EN-P2.m4a"
            $result.IsDefault | Should -BeFalse
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
            $check.NotesMissing | Should -BeTrue
            $check.SummaryMissing | Should -BeTrue
            $check.GenerateMode | Should -Be "both"
        }

        It "Detects mode 'summary' when only NOTES.md exists" {
            Set-Content -Path "$TestBase.NOTES.md" -Value "# Notes" -Encoding UTF8
            $check = Get-MissingMdFiles -BasePath $TestBase
            $check.NotesMissing | Should -BeFalse
            $check.SummaryMissing | Should -BeTrue
            $check.GenerateMode | Should -Be "summary"
        }

        It "Detects mode 'notes' when only SUMMARY.md exists" {
            Set-Content -Path "$TestBase.SUMMARY.md" -Value "# Summary" -Encoding UTF8
            $check = Get-MissingMdFiles -BasePath $TestBase
            $check.NotesMissing | Should -BeTrue
            $check.SummaryMissing | Should -BeFalse
            $check.GenerateMode | Should -Be "notes"
        }

        It "Detects mode 'none' when both MD files exist" {
            Set-Content -Path "$TestBase.NOTES.md" -Value "# Notes" -Encoding UTF8
            Set-Content -Path "$TestBase.SUMMARY.md" -Value "# Summary" -Encoding UTF8
            $check = Get-MissingMdFiles -BasePath $TestBase
            $check.NotesMissing | Should -BeFalse
            $check.SummaryMissing | Should -BeFalse
            $check.GenerateMode | Should -Be "none"
        }

        It "Detects mode 'summary' when OnlyOllama is enabled regardless of NOTES.md" {
            $check = Get-MissingMdFiles -BasePath $TestBase -OnlyOllama
            $check.NotesMissing | Should -BeFalse
            $check.SummaryMissing | Should -BeTrue
            $check.GenerateMode | Should -Be "summary"
        }

        It "Detects mode 'notes' when OnlyLMStudio is enabled regardless of SUMMARY.md" {
            $check = Get-MissingMdFiles -BasePath $TestBase -OnlyLMStudio
            $check.NotesMissing | Should -BeTrue
            $check.SummaryMissing | Should -BeFalse
            $check.GenerateMode | Should -Be "notes"
        }

        It "Correctly detects markdown files when file path contains square brackets [ ]" {
            $bracketDir = Join-Path $env:TEMP "pester_md_bracket_[test]_$(Get-Random)"
            New-Item -ItemType Directory -Path $bracketDir -Force | Out-Null
            try {
                $bracketBase = Join-Path $bracketDir "recording [DQ] [PD] Meet"
                $check1 = Get-MissingMdFiles -BasePath $bracketBase
                $check1.NotesMissing | Should -BeTrue
                $check1.SummaryMissing | Should -BeTrue
                $check1.GenerateMode | Should -Be "both"

                Set-Content -LiteralPath "$bracketBase.NOTES.md" -Value "# Notes" -Encoding UTF8
                $check2 = Get-MissingMdFiles -BasePath $bracketBase
                $check2.NotesMissing | Should -BeFalse
                $check2.SummaryMissing | Should -BeTrue
                $check2.GenerateMode | Should -Be "summary"
            } finally {
                if (Test-Path -LiteralPath $bracketDir) {
                    Remove-Item -LiteralPath $bracketDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Intermediate Processed File Exclusion" {
        It "Excludes preprocessed intermediate files from original audio file candidates" {
            $testFiles = @(
                [PSCustomObject]@{ Name = "recording.SK-D2.mp4"; Extension = ".mp4" },
                [PSCustomObject]@{ Name = "recording.SK-D2.DISTANT-NORM_HP-LP-AC-SN.mp3"; Extension = ".mp3" },
                [PSCustomObject]@{ Name = "recording.SK-D2.PHONE-NORM_HP-LW-SP-LN.mp3"; Extension = ".mp3" },
                [PSCustomObject]@{ Name = "recording.SK-D2.MEETING-NORM_HP-LW-DN.mp3"; Extension = ".mp3" },
                [PSCustomObject]@{ Name = "recording.SK-H2.HALLWAY-NORM_HP-LP-DN-RE.mp3"; Extension = ".mp3" }
            )
            $audioExtensions = @(".m4a", ".flac", ".mp4", ".mp3")
            $filtered = $testFiles | Where-Object {
                $_.Extension.ToLower() -in $audioExtensions -and $_.Name -notmatch '\.(PHONE-NORM_|MEETING-NORM_|DISTANT-NORM_|HALLWAY-NORM_)'
            }
            $filtered.Count | Should -Be 1
            $filtered[0].Name | Should -Be "recording.SK-D2.mp4"
        }
    }

    Context "DisableLLM Mode Handling" {
        It "Sets GenerateMode to none when DisableLLM is switch enabled" {
            $DisableLLM = $true
            $MdCheck = [PSCustomObject]@{
                NotesMissing = $true
                SummaryMissing = $true
                GenerateMode = "both"
            }
            $AnyNonMdMissingOrEmpty = $false
            $NeedsProcessing = if ($DisableLLM) { $AnyNonMdMissingOrEmpty } else { $AnyNonMdMissingOrEmpty -or $MdCheck.NotesMissing -or $MdCheck.SummaryMissing }
            $NeedsProcessing | Should -BeFalse

            $GenerateMode = if ($DisableLLM) { "none" } else { $MdCheck.GenerateMode }
            $GenerateMode | Should -Be "none"
        }
    }

    Context "DJI Video Conversion Integration" {
        BeforeEach {
            $TestDjiDir = Join-Path $env:TEMP "pester_dji_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $TestDjiDir -Force | Out-Null
        }

        AfterEach {
            if ($TestDjiDir -and (Test-Path -LiteralPath $TestDjiDir)) {
                Remove-Item -LiteralPath $TestDjiDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Resolves explicit DJI script path when provided and valid" {
            $dummyScript = Join-Path $TestDjiDir "dummy_dji.ps1"
            Set-Content -LiteralPath $dummyScript -Value 'Write-Host "Dummy DJI"' -Encoding UTF8
            $resolved = Get-DjiScriptPath -ExplicitPath $dummyScript
            $resolved | Should -Be (Get-Item -LiteralPath $dummyScript).FullName
        }

        It "Returns null when explicit DJI script path does not exist" {
            $nonExistent = Join-Path $TestDjiDir "non_existent.ps1"
            $resolved = Get-DjiScriptPath -ExplicitPath $nonExistent
            $resolved | Should -BeNullOrEmpty
        }

        It "Skips conversion when -Skip switch is enabled" {
            $ran = Invoke-DjiConversion -TargetFolder $TestDjiDir -Skip
            $ran | Should -BeFalse
        }

        It "Invokes DJI script with expected scene and silence parameters" {
            $mockDjiScript = Join-Path $TestDjiDir "mock_dji.ps1"
            $paramLog = Join-Path $TestDjiDir "params.log"
            $scriptContent = @"
Param(
    [string]`$sourceFolder,
    [string]`$scene,
    [string]`$checkAudioSilence
)
"sourceFolder=`$sourceFolder|scene=`$scene|checkAudioSilence=`$checkAudioSilence" | Out-File -FilePath "$paramLog" -Encoding UTF8
"@
            Set-Content -LiteralPath $mockDjiScript -Value $scriptContent -Encoding UTF8
            $success = Invoke-DjiConversion -TargetFolder $TestDjiDir -ExplicitScriptPath $mockDjiScript
            $success | Should -BeTrue
            Test-Path -LiteralPath $paramLog | Should -BeTrue
            $loggedParams = Get-Content -LiteralPath $paramLog -Raw
            $expectedScene = if ($IsMacOS) { "special-quality-hw-opt-Apple_M2" } else { "special-quality-hw-dec-cuda" }
            $loggedParams | Should -Match "scene=$expectedScene"
            $loggedParams | Should -Match "checkAudioSilence=0"
        }

        It "Respects explicit Scene parameter override in Invoke-DjiConversion" {
            $mockDjiScript = Join-Path $TestDjiDir "mock_dji_custom.ps1"
            $paramLog = Join-Path $TestDjiDir "params_custom.log"
            $scriptContent = @"
Param(
    [string]`$sourceFolder,
    [string]`$scene,
    [string]`$checkAudioSilence
)
"sourceFolder=`$sourceFolder|scene=`$scene|checkAudioSilence=`$checkAudioSilence" | Out-File -FilePath "$paramLog" -Encoding UTF8
"@
            Set-Content -LiteralPath $mockDjiScript -Value $scriptContent -Encoding UTF8
            $success = Invoke-DjiConversion -TargetFolder $TestDjiDir -ExplicitScriptPath $mockDjiScript -Scene "special-quality-hw-opt-Apple_M2"
            $success | Should -BeTrue
            Test-Path -LiteralPath $paramLog | Should -BeTrue
            $loggedParams = Get-Content -LiteralPath $paramLog -Raw
            $loggedParams | Should -Match "scene=special-quality-hw-opt-Apple_M2"
            $loggedParams | Should -Match "checkAudioSilence=0"
        }
    }

    Context "Converted DJI WebM Duplicate Exclusion" {
        BeforeEach {
            $TestMediaDir = Join-Path $env:TEMP "pester_media_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $TestMediaDir -Force | Out-Null
        }

        AfterEach {
            if ($TestMediaDir -and (Test-Path -LiteralPath $TestMediaDir)) {
                Remove-Item -LiteralPath $TestMediaDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Excludes converted WebM file when original source MP4 exists" {
            $mp4File = Join-Path $TestMediaDir "2026-10-10 PerDiemoEU.EN-M1.mp4"
            $webmFile = Join-Path $TestMediaDir "2026-10-10 PerDiemoEU.EN-M1.CRF-44_LIBSVT-AV1_P2_SO_HW-DEC-CUDA_5120x1440.webm"
            Set-Content -LiteralPath $mp4File -Value "dummy" -Encoding UTF8
            Set-Content -LiteralPath $webmFile -Value "dummy" -Encoding UTF8

            $audioExtensions = @(".m4a", ".flac", ".mp4", ".mp3", ".webm")
            $items = Get-ChildItem -LiteralPath $TestMediaDir -File | Where-Object {
                if ($_.Extension.ToLower() -notin $audioExtensions) { return $false }
                if ($_.Name -match '\.(PHONE-NORM_|MEETING-NORM_|DISTANT-NORM_|HALLWAY-NORM_|ECHOED-NORM_)') { return $false }

                if ($_.Name -match '(\.CRF-\d+|_CRF\d+|[\._]LIBSVT-AV1)') {
                    $baseWithoutDjiSuffix = $_.Name -replace '(\.CRF-\d+|_CRF\d+|[\._]LIBSVT-AV1).*$', ''
                    $hasOriginalMedia = $false
                    foreach ($candExt in @(".mp4", ".mov", ".m4a", ".flac", ".mp3", ".webm")) {
                        $candPath = Join-Path $_.DirectoryName "$baseWithoutDjiSuffix$candExt"
                        if ($candPath -ne $_.FullName -and (Test-Path -LiteralPath $candPath)) {
                            $hasOriginalMedia = $true
                            break
                        }
                    }

                    $hasBaseTranscripts = $false
                    foreach ($candExt in @(".json", ".NOTES.md", ".SUMMARY.md", ".srt", ".tsv", ".vtt", ".txt")) {
                        $candTranscriptPath = Join-Path $_.DirectoryName "$baseWithoutDjiSuffix$candExt"
                        if (Test-Path -LiteralPath $candTranscriptPath) {
                            $hasBaseTranscripts = $true
                            break
                        }
                    }

                    if ($hasOriginalMedia -or $hasBaseTranscripts) { return $false }
                }

                return $true
            }

            $items.Count | Should -Be 1
            $items[0].Name | Should -Be "2026-10-10 PerDiemoEU.EN-M1.mp4"
        }

        It "Retains converted WebM file when original source MP4 exists in _TO_DELETE_ quarantine and no transcripts exist" {
            $toDeleteDir = Join-Path $TestMediaDir "_TO_DELETE_"
            New-Item -ItemType Directory -Path $toDeleteDir -Force | Out-Null
            $mp4File = Join-Path $toDeleteDir "2026-10-10 PerDiemoEU.EN-M1.mp4"
            $webmFile = Join-Path $TestMediaDir "2026-10-10 PerDiemoEU.EN-M1.CRF-44_LIBSVT-AV1_P2_SO_HW-DEC-CUDA_5120x1440.webm"
            Set-Content -LiteralPath $mp4File -Value "dummy" -Encoding UTF8
            Set-Content -LiteralPath $webmFile -Value "dummy" -Encoding UTF8

            $audioExtensions = @(".m4a", ".flac", ".mp4", ".mp3", ".webm")
            $items = Get-ChildItem -LiteralPath $TestMediaDir -File | Where-Object {
                if ($_.Extension.ToLower() -notin $audioExtensions) { return $false }
                if ($_.Name -match '\.(PHONE-NORM_|MEETING-NORM_|DISTANT-NORM_|HALLWAY-NORM_|ECHOED-NORM_)') { return $false }

                if ($_.Name -match '(\.CRF-\d+|_CRF\d+|[\._]LIBSVT-AV1)') {
                    $baseWithoutDjiSuffix = $_.Name -replace '(\.CRF-\d+|_CRF\d+|[\._]LIBSVT-AV1).*$', ''
                    $hasOriginalMedia = $false
                    foreach ($candExt in @(".mp4", ".mov", ".m4a", ".flac", ".mp3", ".webm")) {
                        $candPath = Join-Path $_.DirectoryName "$baseWithoutDjiSuffix$candExt"
                        if ($candPath -ne $_.FullName -and (Test-Path -LiteralPath $candPath)) {
                            $hasOriginalMedia = $true
                            break
                        }
                    }

                    $hasBaseTranscripts = $false
                    foreach ($candExt in @(".json", ".NOTES.md", ".SUMMARY.md", ".srt", ".tsv", ".vtt", ".txt")) {
                        $candTranscriptPath = Join-Path $_.DirectoryName "$baseWithoutDjiSuffix$candExt"
                        if (Test-Path -LiteralPath $candTranscriptPath) {
                            $hasBaseTranscripts = $true
                            break
                        }
                    }

                    if ($hasOriginalMedia -or $hasBaseTranscripts) { return $false }
                }

                return $true
            }

            $items.Count | Should -Be 1
            $items[0].Name | Should -Be "2026-10-10 PerDiemoEU.EN-M1.CRF-44_LIBSVT-AV1_P2_SO_HW-DEC-CUDA_5120x1440.webm"
        }

        It "Excludes converted WebM file when base transcripts exist and original MP4 is in _TO_DELETE_" {
            $toDeleteDir = Join-Path $TestMediaDir "_TO_DELETE_"
            New-Item -ItemType Directory -Path $toDeleteDir -Force | Out-Null
            $mp4File = Join-Path $toDeleteDir "2026-10-10 PerDiemoEU.EN-M1.mp4"
            $notesFile = Join-Path $TestMediaDir "2026-10-10 PerDiemoEU.EN-M1.NOTES.md"
            $webmFile = Join-Path $TestMediaDir "2026-10-10 PerDiemoEU.EN-M1.CRF-44_LIBSVT-AV1_P2_SO_HW-DEC-CUDA_5120x1440.webm"
            Set-Content -LiteralPath $mp4File -Value "dummy" -Encoding UTF8
            Set-Content -LiteralPath $notesFile -Value "# Notes" -Encoding UTF8
            Set-Content -LiteralPath $webmFile -Value "dummy" -Encoding UTF8

            $audioExtensions = @(".m4a", ".flac", ".mp4", ".mp3", ".webm")
            $items = Get-ChildItem -LiteralPath $TestMediaDir -File | Where-Object {
                if ($_.Extension.ToLower() -notin $audioExtensions) { return $false }
                if ($_.Name -match '\.(PHONE-NORM_|MEETING-NORM_|DISTANT-NORM_|HALLWAY-NORM_|ECHOED-NORM_)') { return $false }

                if ($_.Name -match '(\.CRF-\d+|_CRF\d+|[\._]LIBSVT-AV1)') {
                    $baseWithoutDjiSuffix = $_.Name -replace '(\.CRF-\d+|_CRF\d+|[\._]LIBSVT-AV1).*$', ''
                    $hasOriginalMedia = $false
                    foreach ($candExt in @(".mp4", ".mov", ".m4a", ".flac", ".mp3", ".webm")) {
                        $candPath = Join-Path $_.DirectoryName "$baseWithoutDjiSuffix$candExt"
                        if ($candPath -ne $_.FullName -and (Test-Path -LiteralPath $candPath)) {
                            $hasOriginalMedia = $true
                            break
                        }
                    }

                    $hasBaseTranscripts = $false
                    foreach ($candExt in @(".json", ".NOTES.md", ".SUMMARY.md", ".srt", ".tsv", ".vtt", ".txt")) {
                        $candTranscriptPath = Join-Path $_.DirectoryName "$baseWithoutDjiSuffix$candExt"
                        if (Test-Path -LiteralPath $candTranscriptPath) {
                            $hasBaseTranscripts = $true
                            break
                        }
                    }

                    if ($hasOriginalMedia -or $hasBaseTranscripts) { return $false }
                }

                return $true
            }

            $items.Count | Should -Be 0
        }

        It "Retains converted WebM file when neither original media nor base transcripts exist" {
            $webmFile = Join-Path $TestMediaDir "2026-10-10 PerDiemoEU.EN-M1.CRF-44_LIBSVT-AV1_P2_SO_HW-DEC-CUDA_5120x1440.webm"
            Set-Content -LiteralPath $webmFile -Value "dummy" -Encoding UTF8

            $audioExtensions = @(".m4a", ".flac", ".mp4", ".mp3", ".webm")
            $items = Get-ChildItem -LiteralPath $TestMediaDir -File | Where-Object {
                if ($_.Extension.ToLower() -notin $audioExtensions) { return $false }
                if ($_.Name -match '\.(PHONE-NORM_|MEETING-NORM_|DISTANT-NORM_|HALLWAY-NORM_|ECHOED-NORM_)') { return $false }

                if ($_.Name -match '(\.CRF-\d+|_CRF\d+|[\._]LIBSVT-AV1)') {
                    $baseWithoutDjiSuffix = $_.Name -replace '(\.CRF-\d+|_CRF\d+|[\._]LIBSVT-AV1).*$', ''
                    $hasOriginalMedia = $false
                    foreach ($candExt in @(".mp4", ".mov", ".m4a", ".flac", ".mp3", ".webm")) {
                        $candPath = Join-Path $_.DirectoryName "$baseWithoutDjiSuffix$candExt"
                        if ($candPath -ne $_.FullName -and (Test-Path -LiteralPath $candPath)) {
                            $hasOriginalMedia = $true
                            break
                        }
                    }

                    $hasBaseTranscripts = $false
                    foreach ($candExt in @(".json", ".NOTES.md", ".SUMMARY.md", ".srt", ".tsv", ".vtt", ".txt")) {
                        $candTranscriptPath = Join-Path $_.DirectoryName "$baseWithoutDjiSuffix$candExt"
                        if (Test-Path -LiteralPath $candTranscriptPath) {
                            $hasBaseTranscripts = $true
                            break
                        }
                    }

                    if ($hasOriginalMedia -or $hasBaseTranscripts) { return $false }
                }

                return $true
            }

            $items.Count | Should -Be 1
            $items[0].Name | Should -Be "2026-10-10 PerDiemoEU.EN-M1.CRF-44_LIBSVT-AV1_P2_SO_HW-DEC-CUDA_5120x1440.webm"
        }

        It "Extracts filename parameters correctly from converted WebM when original does not exist" {
            $result = Parse-FileNameParameters -FileName "2026-10-10 PerDiemoEU.EN-M1.CRF-44_LIBSVT-AV1_P2_SO_HW-DEC-CUDA_5120x1440.webm"
            $result.Language | Should -Be "en"
            $result.Profile | Should -Be "meeting"
            $result.MinSpeakers | Should -Be 1
            $result.MaxSpeakers | Should -Be 1
            $result.IsDefault | Should -BeFalse
        }
    }
}
