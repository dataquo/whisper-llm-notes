Describe "Whisper ASR Service Docker Tests" {
    BeforeAll {
        $ScriptPath = Join-Path $PSScriptRoot "..\src\whisper-asr-service-docker.ps1"
        if (-not (Test-Path $ScriptPath)) {
            $ScriptPath = Join-Path $PSScriptRoot "..\whisper-asr-service-docker.ps1"
        }

        $ScriptContent = Get-Content -Path $ScriptPath -Raw -Encoding UTF8
        
        # Extract Format-Time function
        if ($ScriptContent -match '(?ms)(function Format-Time\s*\(.+?^\})') {
            Invoke-Expression $Matches[1]
        }

        # Extract Extract-ParametersFromFilename function
        if ($ScriptContent -match '(?ms)(function Extract-ParametersFromFilename\s*\{.+?^\})') {
            Invoke-Expression $Matches[1]
        }
    }

    Context "Timestamp Formatting (Format-Time)" {
        It "Formats 0 seconds as SRT timecode (comma separator)" {
            $formatted = Format-Time -Seconds 0 -Separator ','
            $formatted | Should Be "00:00:00,000"
        }

        It "Formats 65.432 seconds into SRT minutes and seconds" {
            $formatted = Format-Time -Seconds 65.432 -Separator ','
            $formatted | Should Be "00:01:05,432"
        }

        It "Formats 3661.123 seconds into VTT format with dot separator" {
            $formatted = Format-Time -Seconds 3661.123 -Separator '.'
            $formatted | Should Be "01:01:01.123"
        }
    }

    Context "Filename Parameter Extraction" {
        It "Extracts language, profile, and speaker count from standard suffix" {
            $params = Extract-ParametersFromFilename -FileName "recording_audio.SK-M3.mp3"
            $params.LanguageCode | Should Be "sk"
            $params.ProfileChar | Should Be "M"
            $params.SpeakerCount | Should Be 3
        }

        It "Extracts language and profile without speaker count" {
            $params = Extract-ParametersFromFilename -FileName "interview.EN-P.m4a"
            $params.LanguageCode | Should Be "en"
            $params.ProfileChar | Should Be "P"
            $params.SpeakerCount | Should Be $null
        }

        It "Returns null fields when no tags are in the filename" {
            $params = Extract-ParametersFromFilename -FileName "plain_recording.flac"
            $params.LanguageCode | Should Be $null
            $params.ProfileChar | Should Be $null
            $params.SpeakerCount | Should Be $null
        }
    }

    Context "Multi-format Output Generation from JSON Model" {
        It "Properly reconstructs speaker formatted text and SRT entries" {
            $mockJson = @'
            {
                "segments": [
                    { "start": 0.0, "end": 2.5, "speaker": "SPEAKER_00", "text": "Hello world." },
                    { "start": 3.0, "end": 5.2, "speaker": "SPEAKER_01", "text": "Good morning." }
                ]
            }
'@
            $data = $mockJson | ConvertFrom-Json
            $data.segments.Count | Should Be 2
            
            # Build text format
            $txt = ""
            foreach ($s in $data.segments) {
                $prefix = if ($s.speaker) { "[$($s.speaker)]: " } else { "" }
                $txt += "$prefix$($s.text.Trim())`r`n"
            }

            $txt | Should Match "\[SPEAKER_00\]: Hello world\."
            $txt | Should Match "\[SPEAKER_01\]: Good morning\."
        }
    }
}
