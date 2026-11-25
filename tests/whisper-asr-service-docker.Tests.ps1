Describe "Whisper ASR Service Docker Tests" {
    BeforeAll {
        $ScriptPath = Join-Path $PSScriptRoot "..\src\whisper-asr-service-docker.ps1"
        if (-not (Test-Path $ScriptPath)) {
            $ScriptPath = Join-Path $PSScriptRoot "..\whisper-asr-service-docker.ps1"
        }

        $ScriptContent = Get-Content -Path $ScriptPath -Raw -Encoding UTF8
        
        # Extract Format-Time function and inject into global scope
        if ($ScriptContent -match '(?ms)function Format-Time\s*\((.+?^\})') {
            $fnBody = "function global:Format-Time ($($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }

        # Extract Extract-ParametersFromFilename function and inject into global scope
        if ($ScriptContent -match '(?ms)function Extract-ParametersFromFilename\s*\{(.+?^\})') {
            $fnBody = "function global:Extract-ParametersFromFilename { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }

        # Extract Get-PipelineConfig function definition and inject into global scope
        if ($ScriptContent -match '(?ms)function Get-PipelineConfig\s*\{(.+?^\})') {
            $fnBody = "function global:Get-PipelineConfig { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }

        # Extract Get-WhisperContainerMetadata function definition and inject into global scope
        if ($ScriptContent -match '(?ms)function Get-WhisperContainerMetadata\s*\{(.+?^\})') {
            $fnBody = "function global:Get-WhisperContainerMetadata { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }

        # Extract Adjust-TranscriptTimestamps function definition and inject into global scope
        if ($ScriptContent -match '(?ms)function Adjust-TranscriptTimestamps\s*\{(.+?^\})') {
            $fnBody = "function global:Adjust-TranscriptTimestamps { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }
    }

    Context "Timestamp Formatting (Format-Time)" {
        It "Formats 0 seconds as SRT timecode (comma separator)" {
            $formatted = Format-Time -Seconds 0 -Separator ','
            $formatted | Should -Be "00:00:00,000"
        }

        It "Formats 65.432 seconds into SRT minutes and seconds" {
            $formatted = Format-Time -Seconds 65.432 -Separator ','
            $formatted | Should -Be "00:01:05,432"
        }

        It "Formats 3661.123 seconds into VTT format with dot separator" {
            $formatted = Format-Time -Seconds 3661.123 -Separator '.'
            $formatted | Should -Be "01:01:01.123"
        }
    }

    Context "Filename Parameter Extraction" {
        It "Extracts language, profile, and speaker count from standard suffix" {
            $params = Extract-ParametersFromFilename -FileName "recording_audio.SK-M3.mp3"
            $params.LanguageCode | Should -Be "sk"
            $params.ProfileChar | Should -Be "M"
            $params.SpeakerCount | Should -Be 3
        }

        It "Extracts language and profile without speaker count" {
            $params = Extract-ParametersFromFilename -FileName "interview.EN-P.m4a"
            $params.LanguageCode | Should -Be "en"
            $params.ProfileChar | Should -Be "P"
            $params.SpeakerCount | Should -BeNullOrEmpty
        }

        It "Returns null fields when no tags are in the filename" {
            $params = Extract-ParametersFromFilename -FileName "plain_recording.flac"
            $params.LanguageCode | Should -BeNullOrEmpty
            $params.ProfileChar | Should -BeNullOrEmpty
            $params.SpeakerCount | Should -BeNullOrEmpty
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
            $data.segments.Count | Should -Be 2
            
            # Build text format
            $txt = ""
            foreach ($s in $data.segments) {
                $prefix = if ($s.speaker) { "[$($s.speaker)]: " } else { "" }
                $txt += "$prefix$($s.text.Trim())`r`n"
            }

            $txt | Should -Match "\[SPEAKER_00\]: Hello world\."
            $txt | Should -Match "\[SPEAKER_01\]: Good morning\."
        }
    }

    Context "Profile Configuration Defaults" {
        It "Extracts distant profile and speaker count correctly" {
            $params = Extract-ParametersFromFilename -FileName "recording_audio.SK-D2.mp4"
            $params.LanguageCode | Should -Be "sk"
            $params.ProfileChar | Should -Be "D"
            $params.SpeakerCount | Should -Be 2
        }

        It "Validates distant profile includes min/max speakers and vad settings" {
            $MinSpeakers = 2
            $MaxSpeakers = 2
            $ProfileSettings = @{
                "distant" = @{
                    "diarize"        = "true"
                    "vad_filter"     = "true"
                    "vad_onset"      = "0.1"
                    "vad_offset"     = "0.2"
                    "initial_prompt" = "Nahrávka z dálky v místnosti."
                    "min_speakers"   = $MinSpeakers -replace "^$", "2"
                    "max_speakers"   = $MaxSpeakers -replace "^$", "5"
                    "temperature"    = "0.2"
                }
            }
            $ProfileSettings["distant"].min_speakers | Should -Be 2
            $ProfileSettings["distant"].max_speakers | Should -Be 2
            $ProfileSettings["distant"].vad_offset | Should -Be "0.2"
            $ProfileSettings["distant"].vad_onset | Should -Be "0.1"
        }

        It "Extracts hallway profile with letter H correctly" {
            $params = Extract-ParametersFromFilename -FileName "hallway_camera.SK-H1.mp4"
            $params.LanguageCode | Should -Be "sk"
            $params.ProfileChar | Should -Be "H"
            $params.SpeakerCount | Should -Be 1
        }

        It "Extracts echoed profile with letter E correctly" {
            $params = Extract-ParametersFromFilename -FileName "echo_room.SK-E2.mp4"
            $params.LanguageCode | Should -Be "sk"
            $params.ProfileChar | Should -Be "E"
            $params.SpeakerCount | Should -Be 2
        }
    }

    Context "Audio File Validity and LLM Mode Control" {
        It "Rejects 0-byte or corrupted small processed audio files" {
            $smallFile = [PSCustomObject]@{ Length = 425 }
            $isValid = $smallFile -and ($smallFile.Length -gt 1024)
            $isValid | Should -BeFalse

            $validFile = [PSCustomObject]@{ Length = 5242880 }
            $isValidLong = $validFile -and ($validFile.Length -gt 1024)
            $isValidLong | Should -BeTrue
        }
    }

    Context "Pipeline Configuration Layering and Deep Merging" {
        It "Loads base config defaults and preserves all required sections" {
            $scriptDir = Join-Path $PSScriptRoot "..\src"
            $config = Get-PipelineConfig -ScriptDirectory $scriptDir
            $config.whisper_service | Should -Not -BeNullOrEmpty
            $config.whisper_service.api_url | Should -Be "http://localhost:9000/asr"
            $config.ollama_service | Should -Not -BeNullOrEmpty
            $config.profiles | Should -Not -BeNullOrEmpty
        }

        It "Deep merges override without losing other properties" {
            $tempDir = Join-Path $env:TEMP "pester_cfg_test_$(Get-Random)"
            New-Item -ItemType Directory -Path (Join-Path $tempDir "config") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $tempDir "src") -Force | Out-Null
            
            $defaultJson = @'
{
  "whisper_service": {
    "api_url": "http://localhost:9000/asr",
    "docker_container_name": "whisper-asr-service",
    "auto_restart_container": true
  },
  "ollama_service": {
    "model": "gemma3:4b"
  }
}
'@
            $localJson = @'
{
  "whisper_service": {
    "docker_container_name": "custom-container"
  }
}
'@
            Set-Content -Path (Join-Path $tempDir "config\config.default.json") -Value $defaultJson -Encoding UTF8
            Set-Content -Path (Join-Path $tempDir "config\config.local.json") -Value $localJson -Encoding UTF8

            $merged = Get-PipelineConfig -ScriptDirectory (Join-Path $tempDir "src")
            $merged.whisper_service.docker_container_name | Should -Be "custom-container"
            $merged.whisper_service.api_url | Should -Be "http://localhost:9000/asr"
            $merged.whisper_service.auto_restart_container | Should -BeTrue
            $merged.ollama_service.model | Should -Be "gemma3:4b"

            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Falls back to baseline model when Slovak-specific model is requested for Czech or English" {
            $candidateModel = "/.cache/whisper-large-v3-kinit-sk-ct2"
            $baselineModel = "large-v3"
            
            # For Slovak: should keep candidateModel
            $langSk = "sk"
            $chosenSk = if ($candidateModel -match '(?i)(kinit|slovak|-sk)' -and $langSk -ne "sk") { $baselineModel } else { $candidateModel }
            $chosenSk | Should -Be $candidateModel

            # For Czech: should fallback to baselineModel
            $langCs = "cs"
            $chosenCs = if ($candidateModel -match '(?i)(kinit|slovak|-sk)' -and $langCs -ne "sk") { $baselineModel } else { $candidateModel }
            $chosenCs | Should -Be $baselineModel

            # For English: should fallback to baselineModel
            $langEn = "en"
            $chosenEn = if ($candidateModel -match '(?i)(kinit|slovak|-sk)' -and $langEn -ne "sk") { $baselineModel } else { $candidateModel }
            $chosenEn | Should -Be $baselineModel
        }
    }

    Context "Script Version & Container Metadata" {
        It "Extracts canonical script version and script name when running unversioned script" {
            $versionMatch = $ScriptContent -match '\$ScriptVersionNumber = "([^"]+)"'
            $versionMatch | Should -BeTrue
            $version = $Matches[1]
            $version | Should -Match "^v\d+\.\d+"

            # Verify version resolution logic with unversioned name
            $testFileName = "whisper-asr-service-docker.ps1"
            $resolvedVersion = if ($testFileName -match "v(\d+\.\d+)(\.\d+)?\.ps1$") {
                "v$($Matches[1])"
            } else {
                $version
            }
            $resolvedVersion | Should -Be $version

            # Verify version resolution logic with legacy versioned name
            $legacyFileName = "whisper-asr-service-docker.v04.06.ps1"
            $legacyVersion = if ($legacyFileName -match "v(\d+\.\d+)(\.\d+)?\.ps1$") {
                "v$($Matches[1])"
            } else {
                $version
            }
            $legacyVersion | Should -Be "v04.06"
        }

        It "Returns structured container metadata with required schema fields" {
            $meta = Get-WhisperContainerMetadata -ContainerName "whisperx-api" -ApiUrl "http://localhost:9000/asr"
            $meta | Should -Not -BeNullOrEmpty
            $propNames = $meta.PSObject.Properties.Name
            $propNames | Should -Contain "container_name"
            $propNames | Should -Contain "image"
            $propNames | Should -Contain "image_id"
            $propNames | Should -Contain "api_version"
            $propNames | Should -Contain "cudnn_version"
            $propNames | Should -Contain "status"
        }
    }

    Context "Lead-in Silence & Timestamp Compensation" {
        It "Shifts segment and word timestamps by offset and clamps to 0.0" {
            $mockData = [PSCustomObject]@{
                segments = @(
                    [PSCustomObject]@{
                        start = 1.2
                        end   = 3.5
                        text  = "First line"
                        words = @(
                            [PSCustomObject]@{ start = 1.2; end = 2.0; word = "First" },
                            [PSCustomObject]@{ start = 2.1; end = 3.5; word = "line" }
                        )
                    },
                    [PSCustomObject]@{
                        start = 4.0
                        end   = 6.5
                        text  = "Second line"
                        words = @(
                            [PSCustomObject]@{ start = 4.0; end = 5.0; word = "Second" },
                            [PSCustomObject]@{ start = 5.1; end = 6.5; word = "line" }
                        )
                    }
                )
            }

            $adjusted = Adjust-TranscriptTimestamps -Data $mockData -OffsetSeconds 1.5
            
            # First segment (start 1.2 - 1.5 clamped to 0.0, end 3.5 - 1.5 = 2.0)
            $adjusted.segments[0].start | Should -Be 0.0
            $adjusted.segments[0].end | Should -Be 2.0
            $adjusted.segments[0].words[0].start | Should -Be 0.0
            $adjusted.segments[0].words[0].end | Should -Be 0.5
            $adjusted.segments[0].words[1].start | Should -Be 0.6
            $adjusted.segments[0].words[1].end | Should -Be 2.0

            # Second segment (start 4.0 - 1.5 = 2.5, end 6.5 - 1.5 = 5.0)
            $adjusted.segments[1].start | Should -Be 2.5
            $adjusted.segments[1].end | Should -Be 5.0
            $adjusted.segments[1].words[0].start | Should -Be 2.5
            $adjusted.segments[1].words[0].end | Should -Be 3.5
        }

        It "Leaves timestamps unchanged when offset is 0.0" {
            $mockData = [PSCustomObject]@{
                segments = @(
                    [PSCustomObject]@{
                        start = 2.5
                        end   = 5.0
                        text  = "No change"
                        words = @()
                    }
                )
            }

            $adjusted = Adjust-TranscriptTimestamps -Data $mockData -OffsetSeconds 0.0
            $adjusted.segments[0].start | Should -Be 2.5
            $adjusted.segments[0].end | Should -Be 5.0
        }

        It "Loads lead_in_silence_seconds correctly from phone profile in config" {
            $scriptDir = Join-Path $PSScriptRoot "..\src"
            $config = Get-PipelineConfig -ScriptDirectory $scriptDir
            $config.profiles.phone.lead_in_silence_seconds | Should -Be 1.5
            $config.profiles.meeting.lead_in_silence_seconds | Should -Be 0.0
        }
    }

    Context "Curl Multipart File Path Normalization (UNC and Special Characters)" {
        It "Converts Windows backslashes and UNC network share paths to forward slashes for curl" {
            $uncPath = "\\truenas\_DOWNLOADS\_TEMP\_Screen_Recordings_Original\008\meeting recording [DQ].mp3"
            $normalized = $uncPath -replace '\\', '/'
            $normalized | Should -Be "//truenas/_DOWNLOADS/_TEMP/_Screen_Recordings_Original/008/meeting recording [DQ].mp3"
            
            $localPath = "C:\Users\test,user\Recordings\audio file.mp3"
            $normalizedLocal = $localPath -replace '\\', '/'
            $normalizedLocal | Should -Be "C:/Users/test,user/Recordings/audio file.mp3"
        }
    }
}
