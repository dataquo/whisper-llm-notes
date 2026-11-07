<#

 WORKING! 


Based on: https://gemini.google.com/share/6b1dddd87280

v01.00
Gemini said
This PowerShell script is designed to handle your specific requirements: 
- it allows you to pass a file path and a "profile" (like meeting or phone) which automatically adjusts the AI's sensitivity.
- I have used curl.exe explicitly to avoid conflicts with PowerShell's internal curl alias
- I've set the phone profile to use the settings we discovered earlier (disabling the VAD filter) to ensure it catches those quiet voices


Run for a normal meeting in PowerShell:
.\transcribe.ps1 -FilePath "C:\path\to\your\recording.mp4" -Profile meeting

Run for that difficult O2 Phone Call in PowerShell: 
.\transcribe.ps1 -FilePath "C:\path\to\O2-Rozhovor.m4a" -Profile phone


v02.00
Gemini said
- To achieve all five formats (JSON, TXT, SRT, VTT, TSV) in a single pass, the script will request the full JSON data from the API and then use PowerShell's logic to "reconstruct" the other four formats.
- This is the most efficient method because the GPU only works once, and the text conversion happens instantly in your system RAM.

For a Slovak Meeting PowerShell: 
.\transcribe_pro.ps1 -FilePath "C:\Users\Name\Desktop\Meeting.mp4" -Language "sk" -Profile meeting


For the Czech Phone Call PowerShell:
.\transcribe_pro.ps1 -FilePath "C:\Users\Name\Desktop\O2_Call.m4a" -Language "cs" -Profile phone

For a Bilingual (SK/CS) Recording PowerShell (dual language not working):
.\transcribe_pro.ps1 -FilePath "C:\Users\Name\Desktop\Mix.mp3" -Language "sk,cs"


v03.00
Enhanced with proper UNC path support and improved progress visualization

v03.01
- Added support for diarization with speaker labels in all output formats (JSON, TXT, SRT, VTT, TSV) to clearly identify different speakers in meetings and phone calls.
- Implemented a more robust progress bar that reflects the actual stages of processing (uploading, transcribing, generating files) for better user feedback during long transcriptions.
- Added small pauses between file writes to ensure the system has time to flush data to disk before the next read/write operation, improving reliability when generating multiple output formats in a row.
- sending request to the native whisperx endpoint instead of the openai-compatibility layer to ensure all parameters (like diarization) are properly processed and reflected in the output files.
- automated the Container Restart after each transcription to flush GPU VRAM and ensure consistent performance for batch processing multiple files in a row.

v03.02
- the API is not "seeing" them. Because the API doesn't see the language, it has to guess (which is slower) and often gets it wrong, especially with short clips or mixed language content. By explicitly telling the API the language, we can speed up processing and improve accuracy.
- Updated the script to send the language parameter correctly as the URL to the native whisperx endpoint, ensuring that the model processes the audio with the intended language context for better accuracy and faster transcription times.


v03.03
- Integrated FFmpeg audio preprocessing before upload to WhisperX API:
  - Profile-specific pipelines with unique filter chains for each use case
  - Loudness normalization to broadcast standard (-16 LUFS, TP=-1.5dB)
  - Output format: WAV (PCM 16-bit LE) at 16kHz sample rate

## Profile-Specific FFmpeg Pipelines:

| Profile | Suffix | Filters | Description |
|---------|--------|---------|-------------|
| phone | `PHONE-NORM_HP-LW-SP-LN` | highpass(200Hz), lowpass(3500Hz), speechnorm, loudnorm | Narrowband speech for phone calls |
| meeting | `MEETING-NORM_HP-LW-DN` | highpass(80Hz), lowpass(8000Hz), dynaudnorm, loudnorm | Full speech range with dynamic normalization |
| distant | `DISTANT-NORM_HP-LP-AC-SN` | highpass(200Hz), lowpass(4000Hz), acompressor, speechnorm, loudnorm | Compressor + SN for noisy environments |


v03.04
- Integrated FFmpeg audio preprocessing before upload to WhisperX API:
  - Output format: WAV (PCM 16-bit LE) or MP3 (libmp3lame, 64kbps) at 16kHz sample rate
  - Switchable output via commented/uncommented codec parameters


**Inline comments added throughout FFmpeg preprocessing code section.**

v03.05
- Fixed FFREPORT environment variable parsing error that caused log file creation to fail with "Invalid argument" message.
- Added explicit FFREPORT configuration before each FFmpeg command to ensure proper log file generation.
- Log files are now created with the same naming pattern as processed audio files, with timestamp appended before .log extension:
- Example: `O2-Rozhovor.PHONE-NORM_HP-LW-SP-LN.20260414-001224.log`
- FFmpeg report level set to 48 (warning and above) for concise logging.

v03.06
- Added conditional check to skip FFmpeg preprocessing when processed .MP3 or .WAV files already exist, preventing redundant conversions and improving batch processing efficiency.

v04.00 
- Added a new section to generate a summary of the transcript using the Ollama API and the gemma3:4b model. The summary is saved as a markdown (.MD) file in the same directory as the transcript, with the same base name.
- The summary generation is done after chosen transcript file (JSON, TXT, SRT, VTT, TSV) have been created to ensure the full transcript content is available for summarization.

v04.01 
- reverting back to non-stream call for Ollama summarization to simplify the process and avoid issues with streaming responses in PowerShell. 
- The script now waits for the full summary response before saving it to a file, ensuring that the complete summary is captured without complications from handling streamed data.
- The summary prompt has been enhanced to include specific instructions for formatting, language consistency, and inclusion of speaker names and timestamps where relevant, to create a more structured and informative summary based on the transcript content.

v04.01 
- reverting back to non-stream call for Ollama summarization to simplify the process and avoid issues with streaming responses in PowerShell. 
- The script now waits for the full summary response before saving it to a file, ensuring that the complete summary is captured without complications from handling streamed data.
- The summary prompt has been enhanced to include specific instructions for formatting, language consistency, and inclusion of speaker names and timestamps where relevant, to create a more structured and informative summary based on the transcript content.

v04.02 
- added condions to check for existance of the files JSON and MD (summary) before processing the file. 
- If the JSON file already exists, it will skip the transcription step and move directly to summarization (if the MD summary doesn't exist yet). 
- If the MD summary already exists, it will skip both transcription and summarization for that file. 
- This allows for more efficient batch processing by avoiding redundant work on files that have already been processed in previous runs of the script.
- fixed generation of SRT, TXT, VTT, TSV files for cases when JSON file already exists and is being used as source for those formats. 
- Previously, if the JSON file existed, the script would skip transcription but then fail to generate the other formats because it was looking for variables that were only set during the transcription step.
- Now, the script properly loads and parses the existing JSON file to extract the necessary data for generating SRT, TXT, VTT, and TSV files even when skipping the transcription step.
- added debug mode switch (-DebugMode) to enable verbose logging of API URLs, parameters, and other internal state information for troubleshooting and development purposes. When enabled, the script will output additional details about the API request being made, including the full URL with query parameters and the path of the audio file being processed. This can help identify issues with parameter encoding, file paths, or API endpoint configuration during testing and debugging.

v04.03 
- added language extraction from WhisperX JSON response for Ollama summarization:
  - The `$DetectedLanguage` variable extracts the detected language code (`$Data.language`) from the JSON file created by WhisperX API
  - This language information is inserted into the SummaryPrompt to explicitly tell Ollama what language was detected
  - Ensures the summary MD file is generated in the correct detected language rather than inferring from content alone
  - TASK IMPLEMENTED CORRECTLY BUT DISCARTED BECAUSE API DOES NOT PROVIDE CORRECT LANGAUGE TO JSON 

v04.04
- Added transcription logging functionality: captures execution timestamp, profile settings, API parameters, full URL, query string, and timing summary
- Log file naming now matches processed audio pattern: `ProcessedFile.WHISPER.YYYYMMDD-HHMMSS.log`

v04.05
- added comprehensive system information collection to transcription logs, including CPU, RAM, GPU, motherboard, BIOS, disk drives, and operating system details for better context on the hardware environment used for each transcription run. 
- This information is collected using various WMI/CIM classes and included in the JSON log file created for each transcription.

v04.06 
- functionality has already been fully implemented in the `whisper-asr-service-docker.v04.06.ps1` file. 
- Performance Metrics (v04.06) implemented to calculate and log:
- __Total Processing Time__: Calculated from transcription start to end time
- __Real-Time Factor (RTF)__: Ratio of processing time to audio duration (lower is better)
- __Approx. Token Count__: Based on 1 token ≈ 4 characters rule
- __Tokens Per Second (TPS)__: Calculated throughput metric
- These metrics are both displayed in the console output and logged to the JSON log file via the `Write-CompletionSummary` function.
- issues related to special characters in file names(commas, dots, spaces) that aren't being properly escaped when passed to curl.exe. fiex liek ```powershell -F "audio_file=@$TempProcessedFile"```
- The original error occurred because `curl.exe` was receiving the entire transcript (potentially thousands of characters) as a command-line argument, exceeding Windows' MAX_COMMAND_LINE limit. By using PowerShell's native `Invoke-RestMethod`, the JSON payload is sent in the HTTP request body rather than the command line, avoiding this limitation entirely.

v04.07
- implemented logging from docker 
- the concept works but needs some additional adjustment, concept abandoned 

v04.08
- Use proper UTF-8 encoding for all file operations - Ensure all file paths are handled with proper encoding to support Czech/Slovak characters without issues.
- This includes setting the console output encoding and using UTF-8 encoding for all file reads/writes to prevent character corruption in logs and output files.

v05.00
- changed summary generation prompt to "detailed notes" to encourage more comprehensive summaries that include key points, action items, and speaker contributions rather than just a brief overview. This should result in more informative summaries that capture the essence of the meeting or conversation in greater detail.

- Filename Pattern: `file_name.LL-X#.EXT`

Where:

- __LL__ = Language code (2 chars, optional) - e.g., "CZ", "SK", "EN"
- __X__ = Profile indicator (optional): P=phone, M=meeting, D=distant
- __#__ = Speaker count number (optional) - sets both min_speakers and max_speakers
- __EXT__ = File extension

__How it works in the script__:

1. The `Extract-ParametersFromFilename` function uses regex patterns to extract:

   - Language code from pattern like `[lang]-[profile][count]`
   - Profile character (P/M/D)
   - Speaker count number

2. The extracted profile character is converted to full profile names:

   - P → "phone"
   - M → "meeting"
   - D → "distant"

3. If no speaker count is specified, defaults are used:

   - phone: min_speakers=2, max_speakers=2
   - meeting: min_speakers=2, max_speakers=5
   - distant: uses default values

__Examples:__

- `recording.EN-P2.m4a` → English language, phone profile, 2 speakers
- `meeting.SK-M3.mp3` → Slovak language, meeting profile, 3 speakers
- `call.CZ-D4.m4a` → Czech language, distant profile, 4 speakers
- `audio.m4a` (no special suffix) → Uses defaults: phone profile, no speaker override


v05.01
- Created Detailed NOTES.MD summary in LM Studio (v05.01)
- changed Ollama  generation of .MD file to SUMMARY.MD to avoid confusion with the detailed notes generated by LM Studio. 
- The SUMMARY.MD file will contain a concise summary of the transcript, while the NOTES.MD file will contain the more detailed notes generated by LM Studio.
- This way, users can easily distinguish between the two types of summaries and access the level of detail they need.
- Generate NOTES.MD and SUMMARY.MD only if non-existent 
- Append server and model into NOTES.MD and SUMMARY.MD after AI processing

v05.02
- Fixed performance metrics calculation bug that triggered even when no audio transcription occurred
- The issue was that the Performance Metrics section (v04.06) would calculate RTF, TPS, and other metrics for files where only SRT/TXT/VTT/TSV formats were generated from existing JSON files without re-transcribing
- Added conditional check `if ($TranscriptionEndTime)` to wrap the performance metrics calculation - this ensures metrics are only calculated when actual transcription happened (when $TranscriptionEndTime is set)
- Performance metrics now correctly show "N/A" for audio duration and processing time when only format conversion occurs from existing JSON files, rather than showing misleading values
- The fix prevents false RTF/TPS calculations that would occur because the timing variables weren't properly initialized during skip scenarios

v05.03
- Fixed the false "Transcript incomplete" triggers in `_MASTER_WHISPER.ps1` 
- Root Cause: The master script was checking for a generic `.md` file extension, but `whisper-asr-service-docker.v05.03.ps1` generates two separate files: `{basename}.NOTES.md` and `{basename}.SUMMARY.md`. Since neither matched the exact pattern `{basename}.md`, the check incorrectly flagged files as missing transcripts even when all required files existed.
- Solution:-  Updated lines 192-204 to handle `.md` file checking specially - now checks for either `.NOTES.md` or `.SUMMARY.md` variants before marking a file as incomplete.
- The script will now correctly skip processing for files where both `NOTES.md` and `SUMMARY.md` exist, regardless of whether the generic `.md` filename exists.

v05.04
- Added new `GenerateMode` parameter (ValidateSet: "both", "notes", "summary") to selectively generate only missing MD files
- NOTES.md generation now only runs when GenerateMode is "notes" or "both"
- SUMMARY.md generation now only runs when GenerateMode is "summary" or "both"
- This enables the master script to pass targeted GenerateMode based on which files are actually missing
- Benefit: If only SUMMARY.md is missing (NOTES.md already exists), only SUMMARY.md is generated - no unnecessary re-transcription
- Added console output reporting which MD files were generated after processing

v05.05 
- added VRAM Optimization Phase (Unload Ollama) models from VRAM as these models were preventing next whisper ASR iteration from loading into VRAM.
- tested the VRAM optimization phase and confirmed it effectively frees up GPU memory based on https://gemini.google.com/app/a794450ab481b491

v06.00
- Self-Contained Execution Engine Refactoring: Centralized all container lifecycle, FFmpeg DSP, and API execution.
- Deep Configuration Layering (Get-PipelineConfig): Base defaults (config.default.json) + local overrides (config.local.json).
- Deterministic Container Lifecycle: Ensure-WhisperContainerRunning and Restart-WhisperContainer with API health readiness polling.
- Added -DisableLLMs switch parameter to run pure WhisperX transcription without Ollama/LM Studio.
- Multi-Channel Audio Downmix (-ac 1): Enforced mono 16kHz across all DSP profiles (supporting 5.1/7.1 HE-AAC).
- Empty/Corrupt Audio Detection: Validates preprocessed audio > 1KB before upload to prevent Docker API crashes.
- High-Performance Hardware Telemetry: Replaced Get-WmiObject with Get-CimInstance to eliminate 57s remoting freeze in PS7.

v06.01
- Reverberant Room & Echo Audio Optimization: Added 'hallway' (H) and 'echoed' (E) DSP profiles with High-Pass (220Hz), Low-Pass (3700Hz), Spectral Denoise (afftdn), Notch EQ (380Hz), and EBU R128 Loudness Normalization.
- Tuned ASR Decoding: Configured beam_size=1 (greedy search), condition_on_previous_text=false, and repetition_penalty=1.2 to eliminate hallucination loops on muffled CCTV microphone recordings.
- Language-Aware Model Guard: Safeguards language-specific fine-tuned models (e.g. kinit-sk) to be used exclusively for Slovak ('sk'), automatically falling back to standard multilingual 'large-v3' for Czech and English.
- Acoustic Reconstruction LLM Prompting: Added specialized contextual acoustic guidelines into LM Studio (.NOTES.md) and Ollama (.SUMMARY.md) prompt templates to reconstruct distorted phonemes into coherent domain dialogue.
- Dynamic Log Parameters: New-TranscriptionLog dynamically records exact ffmpeg_filters, audio_format, model, and VAD parameters without static hardcoding.
- Multi-format Deduplication: Enhanced Clean-TranscriptText to eliminate consecutive stuttering line loops across TXT, SRT, VTT, and TSV outputs.

v06.02
- Enhanced Comment-Based Help & Discoverability: Added comprehensive parameter convention documentation, profile matrices, and example usages across orchestrator and engine.
- Full ADR 0009 Architecture Specification: Documented idiomatic PowerShell help patterns and CLI discovery UX.
- Explicit Script Name & Version Logging: Split "script_version" into "script_name" and "script_version" (v06.02), eliminating the unversioned fallback string.
- Docker Container & Whisper Service Metadata: Added Get-WhisperContainerMetadata to capture container_name, image, image_id, api_version, cudnn_version, and status in transcription logs.
- Ollama Service Version in Summary: Dynamically queries Ollama /api/version and includes service version in SUMMARY.MD AI processing information.

v06.03
- Lead-in Silence Diarization Priming: Added `lead_in_silence_seconds` configuration parameter to prime PyAnnote's temporal receptive field with FFmpeg `adelay`.
- Automatic Sub-second Timestamp Compensation: Integrated `Adjust-TranscriptTimestamps` to seamlessly subtract the lead-in silence offset across segments, words, and word_segments with 0.0s floor clamping and 3-decimal rounding across all 5 generated output formats (.json, .txt, .srt, .vtt, .tsv).
- Re-calibrated Phone Profile Bandwidth: Retained distinct 200–3500 Hz telephony bandpass with `speechnorm=e=4:r=0.0001:l=1` and -16 LUFS broadcast normalization to cleanly differentiate from wideband meeting profiles.
- Diacritic & Encoding Guard: Enhanced Clean-TranscriptText regex with unicode escape literals (\u2013\u2014) and explicit UTF-8 without BOM streams to prevent diacritic corruption on Czech and Slovak accented text.
- Comprehensive Hardware & Service Telemetry: Extended New-TranscriptionLog to capture Docker container state, image ID, API/cuDNN versions, and lead_in_silence_seconds configuration.

v06.04
- Universal -LiteralPath Enforcement: Replaced standard -Path with -LiteralPath across all PowerShell file provider cmdlets (Test-Path, Get-Content, Move-Item, Get-Item, Remove-Item) to eliminate bracket globbing failures on capture filenames (e.g. [DQ] [PD] Meet...).
- Zero-Failure Processed File Verification: Fixed false "Processed audio file not found" fatal exit after successful FFmpeg audio conversion.
- Resilient FFmpeg Logging: Fixed missing FFREPORT log file detection and movement when paths include square brackets.
- Pester Regression Test Suite: Added test coverage for square bracket path resolution in markdown summarization checks.

v06.05
- High-Visibility Untagged Profile Alerts: Added bright red terminal warning notifying user when no profile tag is defined in filename and recommending standard .LL-X# conventions.
- Upstream WhisperX VAD Silence Guard: Patched whisperx/asr.py to guard against empty VAD segments, eliminating fatal transformers pipeline IndexError: list index out of range on no-speech audio.
- Resilient Zero-Speech PowerShell Pipeline: Replaced falsy array check with strict null checking on $ApiResult.segments; generates valid blank transcripts (.txt, .srt, .vtt, .tsv, .NOTES.md, .SUMMARY.md) to complete batch directories without infinite re-transcription loops.#>



param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,

    [Parameter(Mandatory=$false)]
    [ValidateSet("meeting", "phone", "distant", "hallway", "echoed")]
    [string]$Profile,  # Will be extracted from filename or defaulted

    [Parameter(Mandatory=$false)]
    [ValidateSet("cs", "sk", "en", "ru", "auto", "de", "fr", "it", "pl", "es", "pt", "nl", "fi", "sv", "da", "no", "el", "tr", "hu", "ro", "pl", "uk", "de", "fr", "it", "es", "pt", "nl", "fi", "sv", "da", "no", "el", "tr", "hu", "ro", "pl", "uk")]
    [string]$Language, # Optional language code (e.g., "cs", "sk", "ru") - if not provided, API auto-detects

    [Parameter(Mandatory=$false)]
    [int]$MinSpeakers = $null,  # Override min_speakers from profile defaults (optional)

    [Parameter(Mandatory=$false)]
    [int]$MaxSpeakers = $null,  # Override max_speakers from profile defaults (optional)

    [switch]$DebugMode, # Enable verbose/debug output when specified
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("both", "notes", "summary", "none")]
    [string]$GenerateMode = "both",  # Which MD files to generate: "both", "notes", "summary", or "none"

    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = $null,     # Optional path to config.default.json or config.local.json

    [Parameter(Mandatory=$false)]
    [Alias("DisableLLMs", "SkipLLM", "NoLLM")]
    [switch]$DisableLLM              # When specified, skips all LLM summarization (LM Studio and Ollama)
)

# --- Configuration Loading with Deep Merging (Base Defaults + Local Override) ---
function Get-PipelineConfig {
    param(
        [string]$ExplicitConfigPath = $null,
        [string]$ScriptDirectory = $PSScriptRoot
    )

    $DefaultPath = Join-Path $ScriptDirectory "..\config\config.default.json"
    if (-not (Test-Path $DefaultPath)) {
        $DefaultPath = Join-Path $ScriptDirectory "config\config.default.json"
    }

    $LocalPath = Join-Path $ScriptDirectory "..\config\config.local.json"
    if (-not (Test-Path $LocalPath)) {
        $LocalPath = Join-Path $ScriptDirectory "config\config.local.json"
    }

    $LoadedConfig = [PSCustomObject]@{}

    if (Test-Path $DefaultPath) {
        try {
            $LoadedConfig = Get-Content -Path $DefaultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-Warning "Failed to parse default config at $($DefaultPath): $_"
        }
    }

    $OverridePath = $null
    if ($ExplicitConfigPath -and (Test-Path $ExplicitConfigPath)) {
        $OverridePath = $ExplicitConfigPath
    } elseif (Test-Path $LocalPath) {
        $OverridePath = $LocalPath
    }

    if ($OverridePath) {
        try {
            $OverrideConfig = Get-Content -Path $OverridePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($OverrideConfig) {
                foreach ($prop in $OverrideConfig.PSObject.Properties) {
                    if ($LoadedConfig.PSObject.Properties.Match($prop.Name).Count -gt 0 -and 
                        $LoadedConfig.($prop.Name) -is [PSCustomObject] -and 
                        $prop.Value -is [PSCustomObject]) {
                        foreach ($subProp in $prop.Value.PSObject.Properties) {
                            $LoadedConfig.($prop.Name).($subProp.Name) = $subProp.Value
                        }
                    } else {
                        $LoadedConfig | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force
                    }
                }
            }
        } catch {
            Write-Warning "Failed to parse override config at $($OverridePath): $_"
        }
    }

    return $LoadedConfig
}

# --- Service Readiness and Health Helpers ---
function Test-WhisperServiceHealth {
    param(
        [string]$ApiUrl = "http://localhost:9000/asr",
        [int]$TimeoutSeconds = 2
    )
    try {
        $uri = [System.Uri]$ApiUrl
        $baseUri = "$($uri.Scheme)://$($uri.Authority)"
        $response = Invoke-WebRequest -Uri "$baseUri/docs" -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction SilentlyContinue
        return ($null -ne $response -and $response.StatusCode -ge 200 -and $response.StatusCode -lt 400)
    } catch {
        return $false
    }
}

function Wait-WhisperServiceReady {
    param(
        [string]$ApiUrl = "http://localhost:9000/asr",
        [int]$MaxWaitSeconds = 30
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $MaxWaitSeconds) {
        if (Test-WhisperServiceHealth -ApiUrl $ApiUrl -TimeoutSeconds 1) {
            return $true
        }
        Start-Sleep -Seconds 1
    }
    return $false
}

# Retrieves Docker container and Whisper service metadata for auditing and logging
function Get-WhisperContainerMetadata {
    param(
        [string]$ContainerName,
        [string]$ApiUrl,
        [PSCustomObject]$PipelineConfig
    )

    $pCfg = if ($PipelineConfig) {
        $PipelineConfig
    } elseif ($script:AppConfig) {
        $script:AppConfig
    } elseif (Get-Variable -Name "AppConfig" -ValueOnly -ErrorAction SilentlyContinue) {
        Get-Variable -Name "AppConfig" -ValueOnly -ErrorAction SilentlyContinue
    } else {
        $null
    }

    if (-not $ContainerName -and $pCfg -and $pCfg.whisper_service -and $pCfg.whisper_service.docker_container_name) {
        $ContainerName = $pCfg.whisper_service.docker_container_name
    }
    if (-not $ContainerName) {
        $ContainerName = "whisper-asr-service"
    }

    if (-not $ApiUrl -and $pCfg -and $pCfg.whisper_service -and $pCfg.whisper_service.api_url) {
        $ApiUrl = $pCfg.whisper_service.api_url
    }
    if (-not $ApiUrl) {
        $ApiUrl = "http://localhost:9000/asr"
    }

    $meta = [PSCustomObject]@{
        container_name = $ContainerName
        image          = $null
        image_id       = $null
        api_version    = $null
        cudnn_version  = $null
        status         = $null
    }

    # 1. Inspect Docker container directly if docker command is available
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        try {
            $inspectJson = docker inspect $ContainerName 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $inspectJson) {
                # Try fallback container names if configured name did not match running container
                foreach ($fallbackName in @("whisperx-api", "whisper-asr-service")) {
                    if ($fallbackName -ne $ContainerName) {
                        $fbJson = docker inspect $fallbackName 2>$null
                        if ($LASTEXITCODE -eq 0 -and $fbJson) {
                            $inspectJson = $fbJson
                            $ContainerName = $fallbackName
                            break
                        }
                    }
                }
            }

            if ($inspectJson) {
                $inspect = $inspectJson | ConvertFrom-Json
                if ($inspect -and $inspect.Count -gt 0) {
                    $item = $inspect[0]
                    $meta.container_name = if ($item.Name) { $item.Name.TrimStart('/') } else { $ContainerName }
                    $meta.image          = $item.Config.Image
                    $meta.image_id       = if ($item.Image -and $item.Image.Length -gt 19) { $item.Image.Substring(0, 19) } else { $item.Image }
                    $meta.api_version    = $item.Config.Labels.'org.opencontainers.image.version'
                    $meta.cudnn_version  = $item.Config.Labels.'com.nvidia.cudnn.version'
                    $meta.status         = $item.State.Status
                    return $meta
                }
            }
        } catch {
            # docker inspect failed, fallback to HTTP below
        }
    }

    # 2. HTTP Fallback via /openapi.json if docker inspect did not populate api_version
    if (-not $meta.api_version -and $ApiUrl) {
        try {
            $baseUri = ([System.Uri]$ApiUrl).GetLeftPart([System.UriPartial]::Authority)
            $openapi = Invoke-RestMethod -Uri "$baseUri/openapi.json" -TimeoutSec 2 -ErrorAction Stop
            if ($openapi -and $openapi.info -and $openapi.info.version) {
                $meta.api_version = $openapi.info.version
                if (-not $meta.status) { $meta.status = "online" }
            }
        } catch {
            # API endpoint offline or unreachable
        }
    }

    return $meta
}

function Ensure-WhisperContainerRunning {
    param(
        [PSCustomObject]$PipelineConfig
    )
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return
    }

    $ContainerName = if ($PipelineConfig -and $PipelineConfig.whisper_service -and $PipelineConfig.whisper_service.docker_container_name) {
        $PipelineConfig.whisper_service.docker_container_name
    } else {
        "whisper-asr-service"
    }
    $ApiUrl = if ($PipelineConfig -and $PipelineConfig.whisper_service -and $PipelineConfig.whisper_service.api_url) {
        $PipelineConfig.whisper_service.api_url
    } else {
        "http://localhost:9000/asr"
    }
    $AutoRestart = if ($PipelineConfig -and $PipelineConfig.whisper_service -and ($null -ne $PipelineConfig.whisper_service.auto_restart_container)) {
        [bool]$PipelineConfig.whisper_service.auto_restart_container
    } else {
        $true
    }

    # Check if container exists in Docker
    $containerState = docker inspect --format="{{.State.Status}}" $ContainerName 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($containerState)) {
        if (Test-WhisperServiceHealth -ApiUrl $ApiUrl -TimeoutSeconds 1) {
            return
        }

        Write-Warning "Configured Docker container '$ContainerName' was not found in Docker."
        Write-Warning "If your container uses a different name, configure 'docker_container_name' in 'config/config.local.json'."
        return
    }

    # If container exists but is not running, start it
    if ($containerState -ne "running" -and $AutoRestart) {
        Write-Host "Starting configured Whisper container '$ContainerName'..." -ForegroundColor Yellow
        docker start $ContainerName | Out-Null
        Write-Host "Waiting for Whisper API at $ApiUrl to become ready..." -ForegroundColor Cyan
        if (Wait-WhisperServiceReady -ApiUrl $ApiUrl -MaxWaitSeconds 30) {
            Write-Host "Whisper API is online and ready." -ForegroundColor Green
        } else {
            Write-Warning "Whisper API did not respond within 30 seconds after container start."
        }
    }
}

function Restart-WhisperContainer {
    param(
        [PSCustomObject]$PipelineConfig
    )
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return
    }

    $ContainerName = if ($PipelineConfig -and $PipelineConfig.whisper_service -and $PipelineConfig.whisper_service.docker_container_name) {
        $PipelineConfig.whisper_service.docker_container_name
    } else {
        "whisper-asr-service"
    }
    $ApiUrl = if ($PipelineConfig -and $PipelineConfig.whisper_service -and $PipelineConfig.whisper_service.api_url) {
        $PipelineConfig.whisper_service.api_url
    } else {
        "http://localhost:9000/asr"
    }
    $AutoRestart = if ($PipelineConfig -and $PipelineConfig.whisper_service -and ($null -ne $PipelineConfig.whisper_service.auto_restart_container)) {
        [bool]$PipelineConfig.whisper_service.auto_restart_container
    } else {
        $true
    }

    if (-not $AutoRestart) {
        return
    }

    # Check if container exists in Docker
    $containerState = docker inspect --format="{{.State.Status}}" $ContainerName 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($containerState)) {
        Write-Warning "Cannot restart container: '$ContainerName' was not found in Docker."
        Write-Warning "Check 'docker_container_name' in 'config/config.local.json'."
        return
    }

    Write-Host "Flushing GPU VRAM by restarting Docker container ($ContainerName)..." -ForegroundColor DarkYellow
    docker restart $ContainerName | Out-Null
    if (Wait-WhisperServiceReady -ApiUrl $ApiUrl -MaxWaitSeconds 30) {
        Write-Host "Whisper API is back online and ready for next file." -ForegroundColor Green
    } else {
        Start-Sleep -Seconds 5
    }
}

# --- Load External Configuration using unified layered loader ---
$AppConfig = Get-PipelineConfig -ExplicitConfigPath $ConfigPath

# --- Extract parameters from filename if provided ---
function Extract-ParametersFromFilename {
    param(
        [string]$FileName
    )
    
    # Remove extension to get base name
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    
    # Pattern: file_name.LL-X#.EXT where:
    # - LL = language code (2 chars, optional)
    # - X  = profile indicator (P=phone, M=meeting, D=distant, optional)
    # - #  = speaker count number (optional)
    
    $LanguageCode = $null
    $ProfileChar = $null
    $SpeakerCount = $null
    
    # Extract the last segment after dot that might contain LL-X#
    # Pattern: [lang]-[profile][count] at the end of base name
    if ($BaseName -match "([A-Z]{2})-(.)(\d+)$") {
        $LanguageCode = $Matches[1].ToLower()
        $ProfileChar = $Matches[2]
        $SpeakerCount = [int]$Matches[3]
    } elseif ($BaseName -match "([A-Z]{2})-(.)$") {
        # Language + Profile but no speaker count
        $LanguageCode = $Matches[1].ToLower()
        $ProfileChar = $Matches[2]
        $SpeakerCount = $null
    } elseif ($BaseName -match "-(.)(\d+)$") {
        # Profile + speaker count but no language
        $ProfileChar = $Matches[1]
        $SpeakerCount = [int]$Matches[2]
    } elseif ($BaseName -match "-(.)$") {
        # Just profile, no speaker count
        $ProfileChar = $Matches[1]
        $SpeakerCount = $null
    }
    
    return @{
        LanguageCode = $LanguageCode
        ProfileChar = $ProfileChar
        SpeakerCount = $SpeakerCount
    }
}

# --- 1. Fix Console & Encoding for Czech/Slovak Characters ---
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# --- 2. Helper Functions (Defined first to avoid errors) ---

# Converts seconds to SRT (00:00:00,000) or VTT (00:00:00.000)
function Format-Time([double]$Seconds, [char]$Separator = ',') {
    $ts = [TimeSpan]::FromSeconds($Seconds)
    $ms = ($Seconds - [Math]::Floor($Seconds)) * 1000
    return ("{0:00}:{1:00}:{2:00}{3}{4:000}" -f $ts.Hours, $ts.Minutes, $ts.Seconds, $Separator, [int]$ms)
}

# Saves text as clean UTF-8 without BOM
function Save-Utf8($path, $content) {
    [System.IO.File]::WriteAllText($path, $content, $Utf8NoBom)
}

# Cleans token-level repetitions and silent artifact loops
function Clean-TranscriptText([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    # 1. Reject lines containing only punctuation or dots (e.g. ".", "...", "---")
    if ($Text -match '^[\s.,;:_\-\u2013\u2014]+$') {
        return ""
    }
    # 2. Deduplicate word-level repetitions: e.g. "pozor, pozor, pozor, pozor" -> "pozor"
    $cleaned = [regex]::Replace($Text, '(?i)(\b\w+\b)(?:[,\s]+\1){2,}', '$1')
    # 3. Deduplicate repeated punctuation / dots inside text
    if ($cleaned -match '^\s*(\.{3}\s*)+$') {
        return ""
    }
    return $cleaned.Trim()
}

# Adjusts transcript segment and word timestamps by subtracting lead-in silence offset
function Adjust-TranscriptTimestamps {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Data,
        [Parameter(Mandatory=$true)]
        [double]$OffsetSeconds
    )

    if ($OffsetSeconds -le 0) {
        return $Data
    }

    if ($Data.segments) {
        foreach ($seg in $Data.segments) {
            if ($null -ne $seg.start) {
                $seg.start = [Math]::Round([Math]::Max(0.0, [double]$seg.start - $OffsetSeconds), 3)
            }
            if ($null -ne $seg.end) {
                $seg.end = [Math]::Round([Math]::Max(0.0, [double]$seg.end - $OffsetSeconds), 3)
            }
            if ($seg.words) {
                foreach ($w in $seg.words) {
                    if ($null -ne $w.start) {
                        $w.start = [Math]::Round([Math]::Max(0.0, [double]$w.start - $OffsetSeconds), 3)
                    }
                    if ($null -ne $w.end) {
                        $w.end = [Math]::Round([Math]::Max(0.0, [double]$w.end - $OffsetSeconds), 3)
                    }
                }
            }
        }
    }

    if ($Data.word_segments) {
        foreach ($ws in $Data.word_segments) {
            if ($null -ne $ws.start) {
                $ws.start = [Math]::Round([Math]::Max(0.0, [double]$ws.start - $OffsetSeconds), 3)
            }
            if ($null -ne $ws.end) {
                $ws.end = [Math]::Round([Math]::Max(0.0, [double]$ws.end - $OffsetSeconds), 3)
            }
        }
    }

    return $Data
}

# --- 2a. System Information Function ---

# Collects comprehensive computer system information for logging
function Get-SystemInfo {
    # Hostname
    $hostname = $env:COMPUTERNAME
    
    # CPU Information
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cpuName = $cpu.Name
    $cpuCores = $cpu.NumberOfCores
    $cpuLogicalProcessors = $cpu.NumberOfLogicalProcessors
    $cpuMaxClockSpeed = ($cpu.MaxClockSpeed / 1MB).ToString("0.00") + " GHz"
    
    # Memory (RAM)
    $os = Get-CimInstance Win32_OperatingSystem
    $totalMemoryBytes = $os.TotalVisibleMemorySize
    $totalMemoryGB = [Math]::Round($totalMemoryBytes / 1MB, 2)
    $availableMemoryBytes = $os.FreePhysicalMemory
    $availableMemoryGB = [Math]::Round($availableMemoryBytes / 1MB, 2)
    
    # Physical Memory Modules
    $memoryModules = Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
        @{
            capacity_GB = ([Math]::Round($_.Capacity / 1GB, 0))
            speed_MHz = $_.Speed
            manufacturer = $_.Manufacturer
            partNumber = $_.PartNumber
        }
    }
    
    # GPU Information - Collect all display adapters including NVIDIA
    $allGpus = @()
    
    # Get integrated/primary GPU from Win32_VideoController
    $gpuPrimary = Get-CimInstance Win32_VideoController | Select-Object -First 1
    if ($gpuPrimary) {
        $allGpus += @{
            name = $gpuPrimary.Name
            driver_version = $gpuPrimary.DriverVersion
            device_id = $gpuPrimary.DeviceID
            pnp_id = $gpuPrimary.PNPID
            adapter_type = $gpuPrimary.AdapterType
        }
    }
    
    # Get display adapters using Win32_VideoController (primary GPU info)
    $videoControllers = Get-CimInstance Win32_VideoController
    foreach ($controller in $videoControllers) {
        if (-not ($allGpus | Where-Object { $_.name -eq $controller.Name })) {
            $allGpus += @{
                name = $controller.Name
                driver_version = $controller.DriverVersion
                device_id = $controller.DeviceID
                pnp_id = $controller.PNPID
                memory_size_mb = [Math]::Round($controller.MemorySize / 1MB, 0)
            }
        }
    }
    
    # Try NVIDIA WMI/CIM for additional GPU info (for external NVIDIA GPUs)
    try {
        $nvidiaGpus = Get-CimInstance -Namespace "root\NVIDIA" -Query "SELECT Name, DriverVersion, DeviceID FROM NVIDIA_GPUInformation" -ErrorAction SilentlyContinue 2>$null
        if ($nvidiaGpus) {
            foreach ($ngpu in $nvidiaGpus) {
                # Check if this GPU isn't already in our list
                if (-not ($allGpus | Where-Object { $_.name -eq $ngpu.Name })) {
                    $allGpus += @{
                        name = $ngpu.Name
                        driver_version = $ngpu.DriverVersion
                        device_id = $ngpu.DeviceID
                        is_external_nvidia = $true
                    }
                }
            }
        }
    } catch {
        # NVIDIA WMI not available, continue with other methods
    }
    
    # If we have multiple GPUs, identify the primary (most powerful) one for logging
    if ($allGpus.Count -gt 1) {
        # Prefer external NVIDIA GPU if present
        $nvidiaGpu = $allGpus | Where-Object { $_.name -match "NVIDIA" } | Select-Object -First 1
        if ($nvidiaGpu) {
            $primaryGpu = $nvidiaGpu
            Write-Host "Detected external NVIDIA GPU: $($primaryGpu.name)" -ForegroundColor DarkYellow
        } else {
            # Fall back to first entry (usually primary)
            $primaryGpu = $allGpus[0]
        }
    } else {
        $primaryGpu = if ($allGpus.Count -gt 0) { $allGpus[0] } else { $null }
    }
    
    # Motherboard/Bios
    $bios = Get-CimInstance Win32_BIOS
    $biosManufacturer = $bios.Manufacturer
    $biosVersion = $bios.Version
    $biosReleaseDate = ($bios.ReleaseDate -as [DateTime]).ToString("yyyy-MM-dd")
    
    $motherboard = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
    $motherboardManufacturer = $motherboard.Manufacturer
    $motherboardProduct = $motherboard.Product
    
    # Disk Drives
    $disks = Get-CimInstance Win32_DiskDrive | ForEach-Object {
        @{
            model = $_.Model
            manufacturer = $_.Manufacturer
            size_GB = ([Math]::Round($_.Size / 1GB, 0))
            serialNumber = $_.SerialNumber
            interfaceType = $_.InterfaceType
        }
    }
    
    # Operating System
    $osInfo = Get-CimInstance Win32_OperatingSystem | Select-Object -First 1
    $osCaption = $osInfo.Caption
    $osArchitecture = $osInfo.OSArchitecture
    
    return [PSCustomObject]@{
        hostname = $hostname
        cpu = @{
            name = $cpuName
            cores = $cpuCores
            logical_processors = $cpuLogicalProcessors
            max_clock_speed = $cpuMaxClockSpeed
        }
        ram = @{
            total_gb = $totalMemoryGB
            available_gb = $availableMemoryGB
            modules = @($memoryModules)
        }
        gpu = @{
            name = if ($primaryGpu) { $primaryGpu.name } else { $null }
            driver_version = if ($primaryGpu) { $primaryGpu.driver_version } else { $null }
            all_detected_gpus = @($allGpus)
        }
        motherboard = @{
            manufacturer = $motherboardManufacturer
            product = $motherboardProduct
        }
        bios = @{
            manufacturer = $biosManufacturer
            version = $biosVersion
            release_date = $biosReleaseDate
        }
        disks = @($disks)
        operating_system = @{
            caption = $osCaption
            architecture = $osArchitecture
        }
    }
}

# --- 2a. Extract filename parameters (Language, Profile, Speaker count) ---

$FileName = [System.IO.Path]::GetFileName($FilePath)
$ExtractedParams = Extract-ParametersFromFilename -FileName $FileName

# Determine Language from extracted params or parameter
if ($ExtractedParams.LanguageCode) {
    $Language = $ExtractedParams.LanguageCode
}

# Determine Profile from extracted params or parameter
if ($ExtractedParams.ProfileChar) {
    switch ($ExtractedParams.ProfileChar) {
        "P" { $Profile = "phone" }
        "M" { $Profile = "meeting" }
        "D" { $Profile = "distant" }
        "H" { $Profile = "hallway" }
        "E" { $Profile = "echoed" }
        default { $Profile = "phone" }  # Default fallback
    }
} elseif (-not $Profile) {
    Write-Host "WARNING: No DSP profile specified or tagged in filename '$FileName'. Defaulting to 'phone' profile. Recommended: tag filename as [name].[LL]-[X][#].[ext] (e.g. .SK-M2, .CS-P2, .EN-D1)." -ForegroundColor Red
    $Profile = "phone"
}

# Determine speaker count from extracted params (if available)
if ($ExtractedParams.SpeakerCount) {
    $MinSpeakers = $ExtractedParams.SpeakerCount
    $MaxSpeakers = $ExtractedParams.SpeakerCount
}

# --- 2b. Script Version Detection ---

$ScriptVersionNumber = "v06.05"

$ScriptName = if ($MyInvocation.MyCommand.Path) {
    [System.IO.Path]::GetFileName($MyInvocation.MyCommand.Path)
} else {
    "whisper-asr-service-docker.ps1"
}

# Extract script version dynamically from the filename if versioned (e.g. *.vXX.YY.ps1), else use canonical version
$ScriptVersion = if ($ScriptName -match "v(\d+\.\d+)(\.\d+)?\.ps1$") {
    "v$($Matches[1])"
} else {
    $ScriptVersionNumber
}

# --- 2b. Logging Functions ---

# Creates a new log file for this transcription run (JSON format for machine readability)
function New-TranscriptionLog {
    param(
        [string]$BaseName,
        [string]$OutputDir,
        [string]$Profile,
        [object]$Config,
        [string]$Language,
        [string]$ModelName,
        [string]$FullUrl,
        [string]$QueryString,
        [string]$ProcessedFile,
        [string]$TempProcessedFile,
        [object]$ContainerInfo = $null,
        [PSCustomObject]$PipelineConfig = $null
    )
    
    if (-not $ContainerInfo) {
        $pConfig = if ($PipelineConfig) { $PipelineConfig } elseif ($script:AppConfig) { $script:AppConfig } else { $AppConfig }
        $ContainerInfo = Get-WhisperContainerMetadata -PipelineConfig $pConfig
    }

    # v04.04 - New log filename pattern: ProcessedFile.WHISPER.YYYYMMDD-HHmmss.log (matching processed audio file naming)
    $TimestampSuffix = Get-Date -Format "yyyyMMdd-HHmmss"
    # Extract just the base filename from TempProcessedFile, then append .WHISPER.timestamp.log suffix
    # v04.08 - Use proper path extraction that handles special characters correctly
    $BaseFileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $LogFileName = "$BaseFileName.WHISPER.$TimestampSuffix.log"
    # Combine with output directory to get full path
    # V04.08 Ensure proper path handling with special characters by using explicit quoting
    $LogPath = Join-Path $OutputDir $LogFileName
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $DayOfWeek = (Get-Date).ToString("dddd")
    
    # v04.04/04.05 - Machine-readable JSON format for log file
    $SystemInfo = Get-SystemInfo
    
    $LogData = [ordered]@{
        script_name           = $ScriptName
        script_version        = $ScriptVersion
        execution_time        = $Timestamp
        day_of_week           = $DayOfWeek
        
        container_information = $ContainerInfo
        system_information    = $SystemInfo
        
        configuration_parameters = @{
            profile = $Profile
            diarize = $Config.diarize
            vad_filter = $Config.vad_filter
            vad_onset = $Config.vad_onset
            vad_offset = $Config.vad_offset
            min_speakers = $Config.min_speakers
            max_speakers = $Config.max_speakers
            initial_prompt = if ($Config.initial_prompt) { $Config.initial_prompt.Replace("`r`n", " ") } else { "" }
            temperature = $Config.temperature
            ffmpeg_filters = $Config.ffmpeg_filters
            lead_in_silence_seconds = $Config.lead_in_silence_seconds
            audio_format = $Config.audio_format
            use_neural_enhancer = $Config.use_neural_enhancer
        }
        
        api_parameters = @{
            language = $Language
            model = $ModelName
        }
        
        query_string = $QueryString
        full_api_url = $FullUrl
        
        processing_information = @{
            input_file = $FilePath
            processed_file = $ProcessedFile
        }
    }
    
    # v04.08 Write initial log file as JSON using .NET method for special character paths
    try {
        $jsonOutput = $LogData | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($LogPath, $jsonOutput, $Utf8NoBom)
    } catch {
        Write-Error "Failed to write log file: $_"
        exit
    }
    
    return $LogPath
}

# Appends timing information to the log file
function Add-LogEntry {
    param(
        [string]$LogPath,
        [string]$EventName,
        [datetime]$Timestamp,
        [int]$DurationSeconds = 0
    )
    
    $Line = "@$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") | Event: $EventName | Duration: ${DurationSeconds}s`r`n"
    Add-Content -Path $LogPath -Value $Line
}

# Appends completion summary to the log file (JSON format)
function Write-CompletionSummary {
    param(
        [string]$LogPath,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [int]$TotalSeconds,
        [double]$AudioDuration = 0,
        [double]$ProcessingTime = 0,
        [double]$RTF = 0,
        [int]$TokenCount = 0,
        [double]$TPS = 0
    )
    
    # v04.08 - Use .NET method to read log file with special character paths
    try {
        $jsonContent = [System.IO.File]::ReadAllText($LogPath, $Utf8NoBom)
        $ExistingData = $jsonContent | ConvertFrom-Json
    } catch {
        Write-Error "Failed to read existing log file: $_"
        exit
    }
    
    # Create new object with all properties plus the new timing property
    # Note: system_information and container_information are already in $ExistingData from New-TranscriptionLog
    $UpdatedData = [PSCustomObject]@{
        script_name              = if ($ExistingData.script_name) { $ExistingData.script_name } else { $ScriptName }
        script_version           = $ExistingData.script_version
        execution_time           = $ExistingData.execution_time
        day_of_week              = $ExistingData.day_of_week
        container_information    = $ExistingData.container_information
        system_information       = $ExistingData.system_information
        configuration_parameters = $ExistingData.configuration_parameters
        api_parameters           = $ExistingData.api_parameters
        query_string             = $ExistingData.query_string
        full_api_url             = $ExistingData.full_api_url
        processing_information   = $ExistingData.processing_information
        timing                   = @{
            start_time             = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
            end_time               = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
            total_duration_seconds = $TotalSeconds
        }
        performance_metrics      = @{
            audio_duration_seconds  = [Math]::Round($AudioDuration, 2)
            processing_time_seconds = [Math]::Round($ProcessingTime, 2)
            real_time_factor_rtf    = [Math]::Round($RTF, 3)
            approx_token_count      = $TokenCount
            tokens_per_second_tps   = [Math]::Round($TPS, 2)
        }
    }
    
    # v04.08 Write updated JSON back to file using .NET method for special character paths
    try {
        $jsonOutput = $UpdatedData | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($LogPath, $jsonOutput, $Utf8NoBom)
    } catch {
        Write-Error "Failed to write log file: $_"
        exit
    }
    
    Write-Host "Log file saved: $LogPath" -ForegroundColor Cyan
}

# --- 3. Dynamic Profile Configurations from AppConfig ---
$Config = if ($AppConfig.profiles -and $AppConfig.profiles.$Profile) {
    $pCfg = $AppConfig.profiles.$Profile
    [PSCustomObject]@{
        "diarize"                    = if ($null -ne $pCfg.diarize) { "$($pCfg.diarize)" } else { "true" }
        "vad_filter"                 = if ($null -ne $pCfg.vad_filter) { "$($pCfg.vad_filter)" } else { "true" }
        "vad_onset"                  = if ($null -ne $pCfg.vad_onset) { "$($pCfg.vad_onset)" } else { "0.5" }
        "vad_offset"                 = if ($null -ne $pCfg.vad_offset) { "$($pCfg.vad_offset)" } else { "0.363" }
        "initial_prompt"             = if ($null -ne $pCfg.initial_prompt) { "$($pCfg.initial_prompt)" } else { "" }
        "min_speakers"               = if ($MinSpeakers) { "$MinSpeakers" } elseif ($null -ne $pCfg.min_speakers) { "$($pCfg.min_speakers)" } else { "2" }
        "max_speakers"               = if ($MaxSpeakers) { "$MaxSpeakers" } elseif ($null -ne $pCfg.max_speakers) { "$($pCfg.max_speakers)" } else { "2" }
        "temperature"                = if ($null -ne $pCfg.temperature) { "$($pCfg.temperature)" } else { "0.0" }
        "beam_size"                  = if ($null -ne $pCfg.beam_size) { "$($pCfg.beam_size)" } else { $null }
        "condition_on_previous_text" = if ($null -ne $pCfg.condition_on_previous_text) { "$($pCfg.condition_on_previous_text)" } else { $null }
        "repetition_penalty"         = if ($null -ne $pCfg.repetition_penalty) { "$($pCfg.repetition_penalty)" } else { $null }
        "no_repeat_ngram_size"       = if ($null -ne $pCfg.no_repeat_ngram_size) { "$($pCfg.no_repeat_ngram_size)" } else { $null }
        "ffmpeg_filters"             = if ($null -ne $pCfg.ffmpeg_filters) { "$($pCfg.ffmpeg_filters)" } else { "highpass=f=200,lowpass=f=3500,speechnorm=e=4:r=0.0001:l=1,loudnorm=I=-16:TP=-1.5:LRA=11" }
        "audio_format"               = if ($null -ne $pCfg.audio_format) { "$($pCfg.audio_format)" } else { "mp3" }
        "suffix"                     = if ($null -ne $pCfg.suffix) { "$($pCfg.suffix)" } else { "${Profile}-processed" }
        "model"                      = if ($null -ne $pCfg.model) { "$($pCfg.model)" } else { $null }
        "lead_in_silence_seconds"    = if ($null -ne $pCfg.lead_in_silence_seconds) { [double]$pCfg.lead_in_silence_seconds } else { 0.0 }
        "use_neural_enhancer"        = if ($null -ne $pCfg.use_neural_enhancer) { [bool]$pCfg.use_neural_enhancer } else { $false }
        "use_wpe_dereverb"           = if ($null -ne $pCfg.use_wpe_dereverb) { [bool]$pCfg.use_wpe_dereverb } else { $false }
    }
} else {
    # Fallback default
    [PSCustomObject]@{
        "diarize"                    = "true"
        "vad_filter"                 = "true"
        "vad_onset"                  = "0.5"
        "vad_offset"                 = "0.363"
        "initial_prompt"             = ""
        "min_speakers"               = if ($MinSpeakers) { "$MinSpeakers" } else { "2" }
        "max_speakers"               = if ($MaxSpeakers) { "$MaxSpeakers" } else { "2" }
        "temperature"                = "0.0"
        "beam_size"                  = $null
        "condition_on_previous_text" = $null
        "repetition_penalty"         = $null
        "no_repeat_ngram_size"       = $null
        "ffmpeg_filters"             = "highpass=f=200,lowpass=f=3500,speechnorm=e=4:r=0.0001:l=1,loudnorm=I=-16:TP=-1.5:LRA=11"
        "lead_in_silence_seconds"    = 0.0
        "audio_format"               = "mp3"
        "suffix"                     = "PHONE-NORM_HP-LW-SP-LN"
        "model"                      = $null
        "use_neural_enhancer"        = $false
        "use_wpe_dereverb"           = $false
    }
}

Write-Host "`n ========================  File processing started  ========================" -ForegroundColor Green

# --- Record Start Time for Logging ---
$StartTime = Get-Date
Write-Host "Transcription start time: $($StartTime.ToString("yyyy-MM-dd HH:mm:ss"))" -ForegroundColor Cyan

$BaseName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
$OutputDir = [System.IO.Path]::GetDirectoryName($FilePath)
$FullBase = Join-Path $OutputDir $BaseName

# Define processed file naming and audio format dynamically based on profile config
$ProcessedSuffix = $Config.suffix
$OutputFormat = $Config.audio_format

if ($OutputFormat -eq "wav") {
    $FfMpegOutputParams = "-acodec pcm_s16le"
} else {
    $FfMpegOutputParams = "-acodec libmp3lame -b:a 64k"
}
$TempProcessedFile = "$OutputDir\$BaseName.$ProcessedSuffix.$OutputFormat"

# Check if processed file already exists and is valid to skip redundant FFmpeg conversion
Write-Host "Checking for existing processed file: $TempProcessedFile" -ForegroundColor Gray

$ProcessedFileValid = $false
if (Test-Path -LiteralPath $TempProcessedFile) {
    $fileItem = Get-Item -LiteralPath $TempProcessedFile -ErrorAction SilentlyContinue
    if ($fileItem -and $fileItem.Length -gt 1024) {
        $ProcessedFileValid = $true
    } else {
        $corruptSize = if ($fileItem) { $fileItem.Length } else { 0 }
        Write-Warning "Processed file '$TempProcessedFile' exists but is corrupted/incomplete ($corruptSize bytes). Re-generating with FFmpeg..."
        Remove-Item -LiteralPath $TempProcessedFile -Force -ErrorAction SilentlyContinue
    }
}

if ($ProcessedFileValid) {
    Write-Host "Processed file already exists: $TempProcessedFile" -ForegroundColor Cyan
    Write-Host "Skipping FFmpeg preprocessing..." -ForegroundColor Yellow
} else {
    # Preprocess audio file using FFmpeg with profile filter chain from config
    $ffmpegFilter = $Config.ffmpeg_filters
    if ($Config.lead_in_silence_seconds -and [double]$Config.lead_in_silence_seconds -gt 0) {
        $leadInMs = [int]([double]$Config.lead_in_silence_seconds * 1000)
        if ($ffmpegFilter -notmatch "adelay=") {
            $ffmpegFilter = "adelay=${leadInMs}:all=1,$ffmpegFilter"
        }
        Write-Host "Prepending lead-in silence: $($Config.lead_in_silence_seconds)s (${leadInMs}ms) to prime PyAnnote diarization..." -ForegroundColor DarkYellow
    }
    $FfMpegCmd = "ffmpeg.exe -i `"$FilePath`" -af `"$ffmpegFilter`" $FfMpegOutputParams -ac 1 -ar 16000 `"$TempProcessedFile`" -y"

    # Set FFREPORT environment variable for FFmpeg logging with timestamped filename
    # Use relative filename to avoid Windows drive letter colon parsing issues in FFmpeg
    $LogFileName = "$BaseName.$ProcessedSuffix.$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $FFReportPath = Join-Path $OutputDir $LogFileName
    
    # Ensure the directory exists (in case of special character issues)
    if (-not (Test-Path -LiteralPath $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }
    
    $env:FFREPORT = "file='$LogFileName':level=48"

    # Execute FFmpeg command with proper quoting for special characters
    $FfMpegResult = Invoke-Expression $FfMpegCmd

    if ($LASTEXITCODE -ne 0) { 
        Write-Error "FFmpeg preprocessing failed. Check ffmpeg is installed and accessible.`nExit Code: $LASTEXITCODE"
        exit 1
    }
    
    # Move FFREPORT log file to OutputDir if created in current working directory
    if ((Test-Path -LiteralPath $LogFileName) -and ($LogFileName -ne $FFReportPath)) {
        Move-Item -LiteralPath $LogFileName -Destination $FFReportPath -Force -ErrorAction SilentlyContinue
    }

    # Ensure FFREPORT log file was created
    if (Test-Path -LiteralPath $FFReportPath) {
        Write-Host "FFmpeg report saved: $FFReportPath" -ForegroundColor Cyan
    } else {
        Write-Warning "FFmpeg log file not found at expected location: $FFReportPath"
    }

    # Verify that the generated audio file is valid and non-empty
    $outputFileItem = Get-Item -LiteralPath $TempProcessedFile -ErrorAction SilentlyContinue
    if (-not $outputFileItem -or $outputFileItem.Length -le 1024) {
        $fileSize = if ($outputFileItem) { $outputFileItem.Length } else { 0 }
        Write-Error "Audio preprocessing yielded an empty or invalid audio stream ($fileSize bytes). The source file may contain no valid audio track or silent/corrupt data."
        Remove-Item -LiteralPath $TempProcessedFile -Force -ErrorAction SilentlyContinue
        exit 1
    }

    Write-Host "Success! Audio preprocessed successfully: $TempProcessedFile" -ForegroundColor Green
}

# --- Neural Audio Enhancement Stage (Resemble Enhance: Denoise + Super-Resolution to 44.1kHz) ---
if ($AppConfig.profiles -and $AppConfig.profiles.$Profile -and $AppConfig.profiles.$Profile.use_neural_enhancer) {
    $EffectiveScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
    $EnhanceScript = Join-Path $EffectiveScriptDir "enhance_audio.py"
    if (-not (Test-Path $EnhanceScript)) {
        $EnhanceScript = Join-Path (Get-Location) "src\enhance_audio.py"
    }
    
    $VenvPythonCandidates = @(
        (Join-Path $EffectiveScriptDir "..\.venv\Scripts\python.exe"),
        (Join-Path $EffectiveScriptDir ".venv\Scripts\python.exe"),
        (Join-Path (Get-Location) ".venv\Scripts\python.exe"),
        (Join-Path (Get-Location) "..\.venv\Scripts\python.exe")
    )
    $VenvPython = $null
    foreach ($cand in $VenvPythonCandidates) {
        if (Test-Path $cand) {
            $VenvPython = $cand
            break
        }
    }
    
    $EnhancedFile = "$OutputDir\$BaseName.$ProcessedSuffix.enhanced.wav"
    if (Test-Path -LiteralPath $EnhancedFile) {
        $enhancedItem = Get-Item -LiteralPath $EnhancedFile -ErrorAction SilentlyContinue
        if ($enhancedItem -and $enhancedItem.Length -gt 1024) {
            $TempProcessedFile = $EnhancedFile
            Write-Host "Using existing neural-enhanced audio: $TempProcessedFile" -ForegroundColor Cyan
        }
    } elseif ($VenvPython -and (Test-Path $EnhanceScript)) {
        Write-Host "Applying Resemble Enhance neural restoration (Denoise + Super-Resolution)..." -ForegroundColor Magenta
        $NfeVal = if ($AppConfig.resemble_enhance -and $AppConfig.resemble_enhance.nfe) { $AppConfig.resemble_enhance.nfe } else { 32 }
        $SolverVal = if ($AppConfig.resemble_enhance -and $AppConfig.resemble_enhance.solver) { $AppConfig.resemble_enhance.solver } else { "midpoint" }
        $TauVal = if ($AppConfig.resemble_enhance -and $AppConfig.resemble_enhance.tau) { $AppConfig.resemble_enhance.tau } else { 0.5 }
        
        & $VenvPython $EnhanceScript --input $TempProcessedFile --output $EnhancedFile --nfe $NfeVal --solver $SolverVal --tau $TauVal
        
        if ((Test-Path -LiteralPath $EnhancedFile) -and ((Get-Item -LiteralPath $EnhancedFile).Length -gt 1024)) {
            $TempProcessedFile = $EnhancedFile
            Write-Host "Neural enhancement complete: $TempProcessedFile" -ForegroundColor Green
        } else {
            Write-Warning "Neural enhancement output was not created or empty. Proceeding with FFmpeg audio."
        }
    } else {
        Write-Warning "Resemble Enhance python environment not found. Proceeding with FFmpeg audio."
    }
}

# --- Statistical WPE (Weighted Prediction Error) Dereverberation Stage ---
if ($Config.use_wpe_dereverb) {
    Write-Host "Applying WPE statistical dereverberation (nara_wpe)..." -ForegroundColor Magenta
    $WpeOutputFile = "$OutputDir\$BaseName.$ProcessedSuffix.wpe.$OutputFormat"
    if (Test-Path -LiteralPath $WpeOutputFile) {
        $wpeItem = Get-Item -LiteralPath $WpeOutputFile -ErrorAction SilentlyContinue
        if ($wpeItem -and $wpeItem.Length -gt 1024) {
            $TempProcessedFile = $WpeOutputFile
            Write-Host "Using existing WPE dereverberated audio: $TempProcessedFile" -ForegroundColor Cyan
        }
    } else {
        $EffectiveScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
        $WpeScript = Join-Path $EffectiveScriptDir "dereverb_wpe.py"
        if (-not (Test-Path $WpeScript)) {
            $WpeScript = Join-Path (Get-Location) "src\dereverb_wpe.py"
        }
        
        $VenvPythonCandidates = @(
            (Join-Path $EffectiveScriptDir "..\.venv\Scripts\python.exe"),
            (Join-Path $EffectiveScriptDir ".venv\Scripts\python.exe"),
            (Join-Path (Get-Location) ".venv\Scripts\python.exe"),
            (Join-Path (Get-Location) "..\.venv\Scripts\python.exe")
        )
        $VenvPython = $null
        foreach ($cand in $VenvPythonCandidates) {
            if (Test-Path $cand) {
                $VenvPython = $cand
                break
            }
        }
        
        if ($VenvPython -and (Test-Path $WpeScript)) {
            & $VenvPython $WpeScript --input $TempProcessedFile --output $WpeOutputFile
        } else {
            $containerName = if ($AppConfig.whisper_service -and $AppConfig.whisper_service.docker_container_name) { $AppConfig.whisper_service.docker_container_name } else { "whisperx-api" }
            docker cp $WpeScript "${containerName}:/workspace/dereverb_wpe.py" 2>$null
            docker cp $TempProcessedFile "${containerName}:/workspace/temp_in.audio" 2>$null
            docker exec $containerName python3 /workspace/dereverb_wpe.py --input /workspace/temp_in.audio --output /workspace/temp_out.audio
            docker cp "${containerName}:/workspace/temp_out.audio" $WpeOutputFile 2>$null
            docker exec $containerName rm -f /workspace/temp_in.audio /workspace/temp_out.audio /workspace/dereverb_wpe.py 2>$null
        }

        if ((Test-Path -LiteralPath $WpeOutputFile) -and ((Get-Item -LiteralPath $WpeOutputFile).Length -gt 1024)) {
            $TempProcessedFile = $WpeOutputFile
            Write-Host "WPE dereverberation complete: $TempProcessedFile" -ForegroundColor Green
        } else {
            Write-Warning "WPE output was not created or empty. Proceeding with standard audio."
        }
    }
}


# Check if JSON file already exists - skip to summarization if so
if (-not (Test-Path -LiteralPath "$FullBase.json")) {


    # Requesting verbose_json to get segment data for SRT/VTT/TSV with proper quoting of path
    <#
    The endpoint you are using (/v1/audio/transcriptions) is the OpenAI-compatibility layer. While it is great for standard tools, 
    it often ignores "extra" parameters like diarize because they aren't part of the official OpenAI spec.
    #>
    <# v03.00 - original call to openai-compatibility layer (not working with diarization) 
    $Response = & curl.exe -s -X POST "http://localhost:9000/v1/audio/transcriptions" `
    -H "Content-Type: multipart/form-data" `
    -F "file=@$FilePath" `
    -F "model=whisper-1" `
    -F "language=$Language" `
    -F "initial_prompt=$($Config.initial_prompt)" `
    -F "diarize=$($Config.diarize)" `
    -F "min_speakers=$($Config.min_speakers)" `
    -F "vad_filter=$($Config.vad_filter)" `
    -F "vad_onset=$($Config.vad_onset)" `
    -F "vad_offset=$($Config.vad_offset)" `
    -F "temperature=$($Config.temperature)" `
    -F "response_format=verbose_json"
    #>

    <# v03.01 - original call to native whisperx endpoint with all parameters (working with diarization but language not properly processed)
    # Note: The native endpoint uses 'audio_file' instead of 'file'

    $Response = & curl.exe -s -X POST "http://localhost:9000/asr" `
    -H "Content-Type: multipart/form-data" `
    -F "audio_file=@$FilePath" `
    -F "task=transcribe" `
    -F "language=$Language" `
    -F "model=large-v3" `
    -F "diarize=$($Config.diarize)" `
    -F "min_speakers=$($Config.min_speakers)" `
    -F "max_speakers=5" `
    -F "initial_prompt=$($Config.initial_prompt)" `
    -F "vad_filter=$($Config.vad_filter)" `
    -F "vad_onset=$($Config.vad_onset)" `
    -F "vad_offset=$($Config.vad_offset)" `
    -F "temperature=$($Config.temperature)" 
    #>


    # v03.02 - updated call to native whisperx endpoint with proper language parameter (working with diarization and correct language processing)
    # Prepare the URL with all parameters as Query Strings (with proper URL encoding)
    $BaseUrl = if ($AppConfig -and $AppConfig.whisper_service -and $AppConfig.whisper_service.api_url) { $AppConfig.whisper_service.api_url } else { "http://localhost:9000/asr" }
    
    $BaselineModel = if ($AppConfig.whisper_service -and $AppConfig.whisper_service.model) {
        $AppConfig.whisper_service.model
    } else {
        "large-v3"
    }

    $ModelName = if ($AppConfig.profiles -and $AppConfig.profiles.$Profile -and $AppConfig.profiles.$Profile.model) {
        $candidateModel = $AppConfig.profiles.$Profile.model
        # Safety Guard: Slovak-specific models (e.g. kinit-sk) must strictly only be used for Slovak ('sk')
        if ($candidateModel -match '(?i)(kinit|slovak|-sk)' -and $Language -ne "sk") {
            Write-Host "Note: Profile model '$candidateModel' is Slovak-only. Using baseline '$BaselineModel' for language '$Language'..." -ForegroundColor Cyan
            $BaselineModel
        } else {
            $candidateModel
        }
    } else {
        $BaselineModel
    }
    $DockerContainer = if ($AppConfig -and $AppConfig.whisper_service -and $AppConfig.whisper_service.docker_container_name) { 
        $AppConfig.whisper_service.docker_container_name 
    } else { 
        "whisper-asr-service" 
    }

    # Ensure configured container is running and healthy
    Ensure-WhisperContainerRunning -PipelineConfig $AppConfig

    # Helper function to URL-encode strings
    function ConvertTo-UrlEncoded($String) {
        [System.Web.HttpUtility]::UrlEncode([string]$String)
    }

    # Build query parameters list - strictly include only defined, non-empty values
    $QueryParamList = [System.Collections.Generic.List[string]]::new()
    $QueryParamList.Add("task=transcribe")
    if (-not [string]::IsNullOrWhiteSpace($Language)) {
        $QueryParamList.Add("language=$(ConvertTo-UrlEncoded $Language)")
    }
    if (-not [string]::IsNullOrWhiteSpace($ModelName)) {
        $QueryParamList.Add("model=$(ConvertTo-UrlEncoded $ModelName)")
    }
    if ($null -ne $Config.diarize -and "$($Config.diarize)" -ne "") {
        $QueryParamList.Add("diarize=$(ConvertTo-UrlEncoded $Config.diarize)")
    }
    if ($null -ne $Config.min_speakers -and "$($Config.min_speakers)" -ne "") {
        $QueryParamList.Add("min_speakers=$(ConvertTo-UrlEncoded $Config.min_speakers)")
    }
    if ($null -ne $Config.max_speakers -and "$($Config.max_speakers)" -ne "") {
        $QueryParamList.Add("max_speakers=$(ConvertTo-UrlEncoded $Config.max_speakers)")
    }
    if (-not [string]::IsNullOrWhiteSpace($Config.initial_prompt)) {
        $cleanPrompt = $Config.initial_prompt.Replace("`r`n", " ").Replace("`n", " ")
        $QueryParamList.Add("initial_prompt=$(ConvertTo-UrlEncoded $cleanPrompt)")
    }
    if ($null -ne $Config.vad_filter -and "$($Config.vad_filter)" -ne "") {
        $QueryParamList.Add("vad_filter=$(ConvertTo-UrlEncoded $Config.vad_filter)")
    }
    if ($null -ne $Config.vad_onset -and "$($Config.vad_onset)" -ne "") {
        $QueryParamList.Add("vad_onset=$(ConvertTo-UrlEncoded $Config.vad_onset)")
    }
    if ($null -ne $Config.vad_offset -and "$($Config.vad_offset)" -ne "") {
        $QueryParamList.Add("vad_offset=$(ConvertTo-UrlEncoded $Config.vad_offset)")
    }
    if ($null -ne $Config.temperature -and "$($Config.temperature)" -ne "") {
        $QueryParamList.Add("temperature=$(ConvertTo-UrlEncoded $Config.temperature)")
    }
    if ($null -ne $Config.beam_size -and "$($Config.beam_size)" -ne "") {
        $QueryParamList.Add("beam_size=$(ConvertTo-UrlEncoded $Config.beam_size)")
    }
    if ($null -ne $Config.condition_on_previous_text -and "$($Config.condition_on_previous_text)" -ne "") {
        $QueryParamList.Add("condition_on_previous_text=$(ConvertTo-UrlEncoded $Config.condition_on_previous_text)")
    }
    if ($null -ne $Config.repetition_penalty -and "$($Config.repetition_penalty)" -ne "") {
        $QueryParamList.Add("repetition_penalty=$(ConvertTo-UrlEncoded $Config.repetition_penalty)")
    }
    if ($null -ne $Config.no_repeat_ngram_size -and "$($Config.no_repeat_ngram_size)" -ne "") {
        $QueryParamList.Add("no_repeat_ngram_size=$(ConvertTo-UrlEncoded $Config.no_repeat_ngram_size)")
    }

    $QueryString = $QueryParamList -join "&"
    $FullUrl = if ($QueryString) { "$BaseUrl`?$QueryString" } else { $BaseUrl }

    # Create the transcription log file with all parameters
    $LogPath = New-TranscriptionLog `
        -BaseName $BaseName `
        -OutputDir $OutputDir `
        -Profile $Profile `
        -Config $Config `
        -Language $Language `
        -ModelName $ModelName `
        -FullUrl $FullUrl `
        -QueryString $QueryString `
        -ProcessedFile $TempProcessedFile `
        -TempProcessedFile $TempProcessedFile `
        -PipelineConfig $AppConfig


    # Write BaseURL
    # Write-Host "Base API URL: $BaseUrl" -ForegroundColor Green

    # Debug mode logging (only shown when -DebugMode is specified)
    if ($DebugMode) {
        Write-Host "Full API URL: $FullUrl" -ForegroundColor Green
    }

    # Write Temp Processed File Path
    Write-Host "Audio file for transcription: $TempProcessedFile" -ForegroundColor Green 

    # v04.08 - Check if the processed file exists (not original FilePath) before API call
    if (-not (Test-Path -LiteralPath "$TempProcessedFile")) { 
        Write-Error "Processed audio file not found: $TempProcessedFile"
        exit 
    }

    # Pre-transcription VRAM check: Unload Ollama models if any are occupying GPU memory
    if (-not $DisableLLM -and (Get-Command ollama -ErrorAction SilentlyContinue)) {
        try {
            $ollamaCheck = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 1 -ErrorAction SilentlyContinue
            if ($ollamaCheck) {
                $ActiveModels = & ollama ps 2>$null | Select-Object -Skip 1 | ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ }
                if ($ActiveModels) {
                    foreach ($m in $ActiveModels) {
                        Write-Host "Unloading Ollama model '$m' to free VRAM for WhisperX..." -ForegroundColor Yellow
                        & ollama stop $m | Out-Null
                    }
                    Start-Sleep -Seconds 2
                }
            }
        } catch {
            # Continue
        }
    }

    # --- 4. API Call (Updated to Native Endpoint) ---
    Write-Host "Sending request to Native WhisperX Endpoint..." -ForegroundColor Gray

    Write-Host "Starting Transcription..." -ForegroundColor Cyan
    Write-Host "Profile: $Profile | Language: $Language" -ForegroundColor Yellow

    # Show initial progress state
    Write-Progress -Activity "Processing Audio File" -Status "Starting transcription..." -PercentComplete 20

    # Execute the call using curl.exe for multipart/form-data
    Write-Host "Uploading file: $TempProcessedFile" -ForegroundColor Cyan
    
    try {
        # Build curl arguments for multipart upload
        $curlArgs = @(
            "-s", "-X", "POST", "$FullUrl",
            "-F", "audio_file=@$TempProcessedFile"
        )
        
        # Execute curl command
        $Response = & curl.exe @curlArgs
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "API returned error response" -ForegroundColor Yellow
            Write-Error "Transcription failed with exit code: $LASTEXITCODE"
            exit
        }
        
        # Check if response is empty or contains error
        if (-not $Response -or $Response.Trim().Length -eq 0) {
            Write-Host "API returned empty response" -ForegroundColor Yellow
            Write-Error "Transcription failed. Empty response from API."
            exit
        }
    } catch {
        Write-Host "API returned error response" -ForegroundColor Yellow
        
        if ($_.Exception.Response) {
            try {
                $errorStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorStream)
                $errorBody = $reader.ReadToEnd()
                Write-Error "Transcription failed.`nError: $errorBody"
            } catch {
                Write-Error "Transcription failed.`nError: $($_.Exception.Message)"
            }
        } else {
            Write-Error "Transcription failed with exception: $_"
        }
        
        exit 
    }

    # Parse response as JSON for error handling
    $ApiResult = $null
    
    try {
        $ApiResult = $Response | ConvertFrom-Json
    } catch {
        # Response is not valid JSON - likely an API error message
        Write-Host "API returned non-JSON response (possible error): $Response" -ForegroundColor Yellow
        
        if ($LASTEXITCODE -ne 0) { 
            Write-Host "Transcription failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        }
        
        Write-Error "Transcription failed.`nExit Code: $LASTEXITCODE`nResponse: $Response"
        exit 
    }
    
    # Check for API error messages in the JSON response (GPU errors, CUDA failures, etc.)
    if ($ApiResult.detail) {
        $detailStr = if ($ApiResult.detail -is [string]) {
            $ApiResult.detail
        } else {
            ($ApiResult.detail | ConvertTo-Json -Compress)
        }

        if ($detailStr -match "(?i)(cuda|gpu|memory|device unavailable|batch_size|out of memory)") {
            Write-Host "GPU error detected: $detailStr" -ForegroundColor Red
            Write-Host "Skipping file generation and flushing GPU VRAM..." -ForegroundColor Yellow
            
            # Restart container to recover from GPU out-of-memory state
            Restart-WhisperContainer -PipelineConfig $AppConfig
            Write-Host "Ready for next file." -ForegroundColor Green
            exit 1
        } else {
            # Non-GPU related error (e.g., validation errors)
            Write-Error "Transcription failed.`nAPI Error: $detailStr"
            exit 1
        }
    }
    
    # Show processing state
    Write-Progress -Activity "Processing Audio File" -Status "Processing transcription..." -PercentComplete 50
    
    if ($null -eq $ApiResult.segments) { 
        Write-Error "Transcription returned invalid response (missing segments property).`nResponse: $($Response | ConvertTo-Json)"
        exit 1
    }
    
    if ($ApiResult.segments.Count -eq 0) {
        Write-Warning "No active speech or segments detected in audio for '$FileName'. Generating empty transcript files."
    }
    
    # v04.04 - Record transcription end time immediately after successful API response, before container restart
    $TranscriptionEndTime = Get-Date

    # Compensate for lead-in silence if added during FFmpeg preprocessing
    if ($Config.lead_in_silence_seconds -and [double]$Config.lead_in_silence_seconds -gt 0) {
        $leadInSec = [double]$Config.lead_in_silence_seconds
        Write-Host "Compensating timestamps for lead-in silence (-${leadInSec}s)..." -ForegroundColor Cyan
        $ApiResult = Adjust-TranscriptTimestamps -Data $ApiResult -OffsetSeconds $leadInSec
        $Response = $ApiResult | ConvertTo-Json -Depth 20
    }

    # Use parsed result for file generation
    $Data = $ApiResult
    
    # Show generation state
    Write-Progress -Activity "Processing Audio File" -Status "Generating output files..." -PercentComplete 60

    # 1. JSON (Already contains speaker data)
    Write-Progress -Activity "Processing generated JSON File" -Status "Generating output files..." -PercentComplete 70

    Save-Utf8 "$FullBase.json" $Response

    Start-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formats
    
    # --- 6. Automate the Container Restart--
    Restart-WhisperContainer -PipelineConfig $AppConfig


} else {
    # JSON file exists, skip API call but read it into $Data for other format generation
    Write-Host "JSON file already exists ($($FullBase).json), skipping WhisperX API call..." -ForegroundColor Yellow
    Write-Host "Reading existing JSON to populate data for other format generation..." -ForegroundColor Cyan
    
    # Re-read $Data from existing JSON since segments weren't populated in this run
    try {
        $JsonContent = [System.IO.File]::ReadAllText("$FullBase.json", $Utf8NoBom)
        $ApiResult = $JsonContent | ConvertFrom-Json
        if ($null -eq $ApiResult.segments) { 
            Write-Error "Existing JSON file is invalid (missing segments property). Please re-run transcription.`nResponse: $($JsonContent)"
            exit 
        }
        $Data = $ApiResult
        Write-Host "Success! Successfully loaded data from existing JSON." -ForegroundColor Green
    } catch {
        Write-Error "Failed to read existing JSON file: $_" -ForegroundColor Red
        exit 
    }
}



# --- 5. Generate All 4 Formats (Updated with Speaker Labels) ---
Write-Progress -Activity "Generating files with Speaker Labels..." -Status "Generating output files..." -PercentComplete 80
Start-Sleep -Seconds 1


# 2. TXT (Rebuilt from segments to include speakers)
Write-Progress -Activity "Generating TXT File with different speakers" -Status "Generating output files..." -PercentComplete 85

$txt = ""
$lastCleanedText = ""
$lastSpeaker = ""
foreach ($s in $Data.segments) {
    $cleanedText = Clean-TranscriptText $s.text
    if ($cleanedText) {
        # Deduplicate consecutive identical short utterances (e.g. repeated "Môžeš." or "Dobre.")
        if ($cleanedText -eq $lastCleanedText -and $s.speaker -eq $lastSpeaker) {
            continue
        }
        $speakerPrefix = if ($s.speaker) { "[$($s.speaker)]: " } else { "" }
        $txt += "$speakerPrefix$cleanedText`r`n"
        $lastCleanedText = $cleanedText
        $lastSpeaker = $s.speaker
    }
}
Save-Utf8 "$FullBase.txt" $txt
<##>
Start-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formats


# 3. SRT
Write-Progress -Activity "Generating SRT File with different speakers" -Status "Generating output files..." -PercentComplete 90

$srt = ""
$srtIndex = 1
$lastCleanedText = ""
$lastSpeaker = ""
for ($i=0; $i -lt $Data.segments.Count; $i++) {
    $s = $Data.segments[$i]
    $cleanedText = Clean-TranscriptText $s.text
    if ($cleanedText) {
        if ($cleanedText -eq $lastCleanedText -and $s.speaker -eq $lastSpeaker) {
            continue
        }
        $speakerPrefix = if ($s.speaker) { "[$($s.speaker)] " } else { "" }
        $srt += "$srtIndex`r`n"
        $srt += "$(Format-Time $s.start) --> $(Format-Time $s.end)`r`n"
        $srt += "$speakerPrefix$cleanedText`r`n`r`n"
        $srtIndex++
        $lastCleanedText = $cleanedText
        $lastSpeaker = $s.speaker
    }
}
Save-Utf8 "$FullBase.srt" $srt

Start-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formats


# 4. VTT
Write-Progress -Activity "Generating VTT File with different speakers" -Status "Generating output files..." -PercentComplete 95

$vtt = "WEBVTT`r`n`r`n"
$lastCleanedText = ""
$lastSpeaker = ""
foreach ($s in $Data.segments) {
    $cleanedText = Clean-TranscriptText $s.text
    if ($cleanedText) {
        if ($cleanedText -eq $lastCleanedText -and $s.speaker -eq $lastSpeaker) {
            continue
        }
        $speakerPrefix = if ($s.speaker) { "[$($s.speaker)] " } else { "" }
        $vtt += "$(Format-Time $s.start '.') --> $(Format-Time $s.end '.')`r`n"
        $vtt += "$speakerPrefix$cleanedText`r`n`r`n"
        $lastCleanedText = $cleanedText
        $lastSpeaker = $s.speaker
    }
}
Save-Utf8 "$FullBase.vtt" $vtt

Start-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formats



# 5. TSV
Write-Progress -Activity "Generating TSV File with different speakers" -Status "Generating output files..." -PercentComplete 98

$tsv = "start`tend`tspeaker`ttext`r`n"
$lastCleanedText = ""
$lastSpeaker = ""
foreach ($s in $Data.segments) {
    $cleanedText = Clean-TranscriptText $s.text
    if ($cleanedText) {
        if ($cleanedText -eq $lastCleanedText -and $s.speaker -eq $lastSpeaker) {
            continue
        }
        $tsv += "$($s.start)`t$($s.end)`t$($s.speaker)`t$cleanedText`r`n"
        $lastCleanedText = $cleanedText
        $lastSpeaker = $s.speaker
    }
}
Save-Utf8 "$FullBase.tsv" $tsv

Start-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formatsStart-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formats

# Processed audio files are kept for review/analysis. To delete automatically, remove this block.
Write-Progress -Activity "Processing Audio File" -Status "Completed!" -PercentComplete 100 -Completed

Start-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formatsStart-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formats

Write-Host "Success! All files TXT, SRT, VTT, and TSV created in: $OutputDir" -ForegroundColor Green




# --- 7. Calculate Performance Metrics (v04.06) ---
# Only calculate performance metrics if actual transcription occurred
# ($TranscriptionEndTime is only set when we go through the WhisperX API call)
if ($TranscriptionEndTime -and $LogPath -and (Test-Path -LiteralPath $LogPath)) {
    # Get audio duration and calculate processing metrics

    # Try to get duration from API response first, otherwise calculate from segments
    $AudioDuration = if ($Data.duration) { 
        [Math]::Round($Data.duration, 2) 
    } elseif ($Data.segments -and $Data.segments.Count -gt 0) {
        # Calculate duration from first segment start to last segment end
        $firstStart = $Data.segments[0].start
        $lastEnd = $Data.segments[-1].end
        [Math]::Round($lastEnd - $firstStart, 2)
    } else { 
        0 
    }

    # Processing time is the difference between transcription start and end
    $ProcessingTime = [Math]::Round(($TranscriptionEndTime - $StartTime).TotalSeconds, 2)

    # Calculate RTF (Real-Time Factor): lower is better (RTF < 1.0 means faster than audio duration)
    $RTF = if ($AudioDuration -gt 0) { [Math]::Round($ProcessingTime / $AudioDuration, 3) } else { 0 }

    # Approximate token count: 1 token ≈ 4 characters (or ~3-4 words)
    $txtContent = [System.IO.File]::ReadAllText("$FullBase.txt", $Utf8NoBom)
    $charCount = $txtContent.Length
    $ApproxTokenCount = [Math]::Round($charCount / 4, 0)

    # Calculate TPS (Tokens Per Second)
    $TPS = if ($ProcessingTime -gt 0) { [Math]::Round($ApproxTokenCount / $ProcessingTime, 2) } else { 0 }

    Write-Host "`n=====================  Performance Metrics (v04.06)  ======================" -ForegroundColor Cyan
    Write-Host "Total Processing Time:    $($ProcessingTime)s" -ForegroundColor White
    Write-Host "Audio Duration:           $(if($AudioDuration -gt 0){ "$($AudioDuration)s" } else { "N/A" })" -ForegroundColor White
    Write-Host "Real-Time Factor (RTF):   $(if($RTF -gt 0){ "$($RTF)x" } else { "N/A" })" -ForegroundColor $(if($RTF -lt 1.0){"Green"}else{"Yellow"})
    Write-Host "Approx. Token Count:      $ApproxTokenCount tokens" -ForegroundColor White
    Write-Host "Tokens Per Second (TPS):  $($TPS)x" -ForegroundColor $(if($TPS -gt 50){"Cyan"}else{"White"})
    Write-Host "==========================================================================`n" -ForegroundColor Cyan

    # --- 7b. Write completion summary to log file (after Whisper API, before Ollama) ---
    $TotalSeconds = [Math]::Round(($TranscriptionEndTime - $StartTime).TotalSeconds)
    
    try {
        Write-CompletionSummary `
            -LogPath $LogPath `
            -StartTime $StartTime `
            -EndTime $TranscriptionEndTime `
            -TotalSeconds $TotalSeconds `
            -AudioDuration $AudioDuration `
            -ProcessingTime $ProcessingTime `
            -RTF $RTF `
            -TokenCount $ApproxTokenCount `
            -TPS $TPS
    } catch {
        Write-Warning "Could not write completion summary to log: $_"
    }
}

# --- 8. Remote OpenAI-Compatible API Summarization Step (LM Studio on MacBook Pro) ---
# Only generate NOTES.md if GenerateMode includes "notes" or "both" AND file doesn't already exist
if (-not $DisableLLM -and ($GenerateMode -eq "notes" -or $GenerateMode -eq "both") -and -not (Test-Path -LiteralPath "$FullBase.NOTES.md")) {
    Write-Host "Starting to process generate detailed notes with LM Studio..." -ForegroundColor Cyan
    
    Write-Progress -Activity "Generating Detailed Notes with LM Studio" -Status "Creating NOTES.md summary..." -PercentComplete 67
    
$RemoteApiUrl = if ($AppConfig -and $AppConfig.lm_studio_service -and $AppConfig.lm_studio_service.api_url) { $AppConfig.lm_studio_service.api_url } else { "http://10.0.0.162:1234/v1" }
$LmStudioEndpoint = if ($RemoteApiUrl -match "/chat/completions$") { $RemoteApiUrl } else { "$RemoteApiUrl/chat/completions" }
$RemoteModel = if ($AppConfig -and $AppConfig.lm_studio_service -and $AppConfig.lm_studio_service.model) { $AppConfig.lm_studio_service.model } else { "qwen/qwen3.6-35b-a3b" }
$TranscriptPath = "$FullBase.txt"

# Read the transcript file content to include in the prompt
if (Test-Path -LiteralPath $TranscriptPath) {
    $TranscriptContent = [System.IO.File]::ReadAllText($TranscriptPath, $Utf8NoBom)
} else {
    Write-Warning "Transcript file not found: $TranscriptPath. Skipping notes generation."
    $TranscriptContent = ""
}

# Build the summary prompt for LM Studio with acoustic reconstruction context for echoed/hallway environments
$AcousticContextPrompt = if ($Profile -in @('hallway', 'echoed')) {
@"
ACOUSTIC CONTEXT & RECONSTRUCTION GUIDELINES:
- This recording was captured in a reverberant acoustic space with echo and distance (hallway/corridor camera).
- The raw transcript may contain phonetic misinterpretations, slurred syllables, or acoustic stuttering artifacts.
- In your structured notes:
  1. Reconstruct the plausible and coherent meaning of sentences by correcting obvious phonetic transcription errors and grammatical agreements in the target language (Slovak / Czech / English).
  2. Filter out repeating filler loops or acoustic stutter fragments.
  3. Extract the underlying genuine conversation, intent, action items, and speaker exchanges clearly.
  4. Do not hallucinate unrelated facts; keep reconstructions strictly faithful to the conversational context.

"@
} else {
    ""
}

$SummaryPromptRemote = @"
Please create a detailed structured notes of this audio transcript in the original language of the transcript file. 

$AcousticContextPrompt
Rules:
1. Include speaker names if possible (or speaker labels if not possible to deduce names)
2. Speaker names can be derived from topic or transcript (if name mentioned) 
3. include timestamps if deemed relevant to the content of the conversation (e.g., important decisions, action items, topic changes) 

TRANSCRIPT TOPIC: $BaseName 
- the initial number is hardcoded date in the format YYYY-MM-DD or YYMMDD, please always format the date as "DD MonthName YYYY" (e.g., 14 April 2024) in the notes file
- based on the date,include the day of the week as well (e.g., Sunday, 14 April 2024)
- the initial number is followed by a descriptive title that can be used to understand the topic of the conversation and potentially identify speakers 

TRANSCRIPT CONTENT:
$TranscriptContent

Format: 
- The notes file should be in markdown .MD format with clear sections and bullet points where appropriate. 
- Return ONLY the markedown content without any additional explanations or text

Language: 
- The whole notes MD  file should be in the same language as the transcript file
- if the transcript is in Czech, write the notes in Czech. If the transcript is in Slovak, write the notes in Slovak. If the transcript is in English, write the notes in English.
- it will be either Czech or Slovak or English, always pick one and only one for the whole MD file 
- SPEAKER_00, SPEAKER_01, and so on are exluded from consideration when determining the language of the transcript, so if the transcript contains "SPEAKER_00: Dobrý den, jak se máte?" the summary should be in Czech, not in English, because the actual content of the transcript is in Czech.

"@

# Build the request body for OpenAI-compatible API
$RequestBodyRemote = @{
    model   = $RemoteModel
    messages = @(
        @{
            role    = "system"
            content = "You are a helpful assistant that creates detailed meeting notes from audio transcripts."
        }
        @{
            role    = "user"
            content = $SummaryPromptRemote
        }
    )
    stream  = $false
} | ConvertTo-Json

try {
    # Use Invoke-RestMethod for the OpenAI-compatible API call
    $RemoteSummaryResponse = Invoke-RestMethod -Uri $LmStudioEndpoint `
                                              -Method POST `
                                              -ContentType "application/json" `
                                              -Body $RequestBodyRemote
                                             
    if ($RemoteSummaryResponse.choices[0].message.content) {
        # Save the notes file as $($FullBase).NOTES.md (with capital NOTES)
        $NotesContent = $RemoteSummaryResponse.choices[0].message.content
        
        # Append parameters section in markdown format
        $ParametersSection = @"

---
## AI Processing Information

### LM Studio (NOTES.MD)

| Parameter | Value |
| :--- | :--- |
| API Server | $LmStudioEndpoint |
| Model | $RemoteModel |
| Transcript Path | $TranscriptPath |
| Inference | LM Studio |


"@
        
        Save-Utf8 "$($FullBase).NOTES.md" ($NotesContent + $ParametersSection)
        Write-Host "Success! Detailed notes created: $($FullBase).NOTES.md" -ForegroundColor Green
    } else {
        Write-Host "LM Studio returned empty response. Check if LM Studio is running on $RemoteApiUrl with model '$RemoteModel'." -ForegroundColor Red
    }
} catch {
    Write-Host "LM Studio summarization failed: $_. Ensure LM Studio is running at $RemoteApiUrl with model '$RemoteModel' available." -ForegroundColor Red
}
} else {
    if (-not $DisableLLM -and ($GenerateMode -eq "notes" -or $GenerateMode -eq "both")) {
        Write-Host "NOTES.md already exists, skipping..." -ForegroundColor Yellow
    }
}

# --- 8b. Ollama Summarization Step (original) ---
# Only generate SUMMARY.MD if GenerateMode includes "summary" or "both" AND file doesn't already exist
if (-not $DisableLLM -and ($GenerateMode -eq "summary" -or $GenerateMode -eq "both") -and -not (Test-Path -LiteralPath "$FullBase.SUMMARY.md")) {
    Write-Host "Starting to process generate summary with Ollama..." -ForegroundColor Cyan
    
    Write-Progress -Activity "Generating Summary with Ollama" -Status "Creating SUMMARY.MD summary..." -PercentComplete 68

$LocalApiUrl = if ($AppConfig -and $AppConfig.ollama_service -and $AppConfig.ollama_service.api_url) { $AppConfig.ollama_service.api_url } else { "http://localhost:11434" }
$OllamaEndpoint = if ($LocalApiUrl -match "/api/generate$") { $LocalApiUrl } else { "$LocalApiUrl/api/generate" }
$OllamaModel = if ($AppConfig -and $AppConfig.ollama_service -and $AppConfig.ollama_service.model) { $AppConfig.ollama_service.model } else { "gemma3:4b" }
$TranscriptPath = "$FullBase.txt"

# Read the transcript file content to include in the prompt
if (Test-Path -LiteralPath $TranscriptPath) {
    $TranscriptContent = [System.IO.File]::ReadAllText($TranscriptPath, $Utf8NoBom)
} else {
    Write-Warning "Transcript file not found: $TranscriptPath. Skipping notes generation."
    $TranscriptContent = ""
}

$SummaryPrompt = @"
Please create a structured summary of this audio transcript in the original language of the transcript file. 

$AcousticContextPrompt
Rules:
1. Include speaker names if possible (or speaker labels if not possible to deduce names)
2. Speaker names can be derived from topic or transcript (if name mentioned) 
3. include timestamps if deemed relevant to the content of the conversation (e.g., important decisions, action items, topic changes) 

TRANSCRIPT TOPIC: $BaseName 
- the initial number is hardcoded date in the format YYYY-MM-DD or YYMMDD, please always format the date as "DD MonthName YYYY" (e.g., 14 April 2024) in the summary file
- based on the date,include the day of the week as well (e.g., Sunday, 14 April 2024)
- the initial number is followed by a descriptive title that can be used to understand the topic of the conversation and potentially identify speakers 

TRANSCRIPT CONTENT:
$TranscriptContent

Format: 
- The summary file should be in markdown .MD format with clear sections and bullet points where appropriate. 
- Return ONLY the markedown content without any additional explanations or text

Language: 
- The whole summary MD  file should be in the same language as the transcript file
- if the transcript is in Czech, write the summary in Czech. If the transcript is in Slovak, write the summary in Slovak. If the transcript is in English, write the summary in English.
- it will be either Czech or Slovak or English, always pick one and only one for the whole MD file 
- SPEAKER_00, SPEAKER_01, and so on are exluded from consideration when determining the language of the transcript, so if the transcript contains "SPEAKER_00: Dobrý den, jak se máte?" the summary should be in Czech, not in English, because the actual content of the transcript is in Czech.

"@

try {
    # Build the request body as a PowerShell object, then convert to JSON
    $RequestBody = @{
        model   = $OllamaModel
        prompt  = $SummaryPrompt
        stream  = $false
    } | ConvertTo-Json
    
    # Use Invoke-RestMethod instead of curl.exe to avoid command-line length limitations
    $SummaryResponse = Invoke-RestMethod -Uri $OllamaEndpoint `
                                         -Method POST `
                                         -ContentType "application/json" `
                                         -Body $RequestBody

                                         
    if ($SummaryResponse.response) {
        # Query Ollama version if reachable
        $OllamaVersion = try {
            $OllamaBaseUri = ([System.Uri]$OllamaEndpoint).GetLeftPart([System.UriPartial]::Authority)
            $vRes = Invoke-RestMethod -Uri "$OllamaBaseUri/api/version" -TimeoutSec 2 -ErrorAction Stop
            if ($vRes -and $vRes.version) { $vRes.version } else { $null }
        } catch {
            $null
        }

        $OllamaVersionRow = if ($OllamaVersion) { "`r`n| Service Version | Ollama $OllamaVersion |" } else { "" }

        # Append parameters section in markdown format
        $ParametersSection = @"

---
## AI Processing Information

### Ollama (SUMMARY.MD)

| Parameter | Value |
| :--- | :--- |
| API Server | $OllamaEndpoint |$OllamaVersionRow
| Model | $OllamaModel |
| Transcript Path | $TranscriptPath |
| Inference | Ollama |

"@
        
        Save-Utf8 "$FullBase.SUMMARY.md" ($SummaryResponse.response + $ParametersSection)
        Write-Host "Success! Summary MD created: $($FullBase).SUMMARY.md" -ForegroundColor Green
    } else {
        Write-Host "Ollama returned empty response. Check if Ollama is running with model '$OllamaModel'." -ForegroundColor Red
    }
} catch {
    Write-Host "Ollama summarization failed: $_. Ensure Ollama is running and the model '$OllamaModel' is available." -ForegroundColor Red
}
} else {
    if ($DisableLLM -or $GenerateMode -eq "none") {
        # LLM summarization disabled via -DisableLLMs
    } elseif (Test-Path -LiteralPath "$FullBase.SUMMARY.md") {
        Write-Host "SUMMARY.md already exists, skipping..." -ForegroundColor Yellow
    }
}

# Report what was generated
if ($DisableLLM -or $GenerateMode -eq "none") {
    Write-Host "LLM summarization skipped (-DisableLLMs active)." -ForegroundColor DarkGray
} else {
    $GeneratedFiles = @()
    if (Test-Path -LiteralPath "$FullBase.NOTES.md") { $GeneratedFiles += "NOTES.md" }
    if (Test-Path -LiteralPath "$FullBase.SUMMARY.md") { $GeneratedFiles += "SUMMARY.md" }
    if ($GeneratedFiles.Count -gt 0) {
        Write-Host "Generated MD files: $($GeneratedFiles -join ', ')" -ForegroundColor Cyan
    }
}



# --- 9a VRAM Optimization Phase (Unload Ollama) v05.05---
Write-Host "--- Checking VRAM Allocation ---" -ForegroundColor Cyan

if (-not $DisableLLM -and (Get-Command ollama -ErrorAction SilentlyContinue)) {
    try {
        $ollamaCheck = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 1 -ErrorAction SilentlyContinue
        if ($ollamaCheck) {
            # Dynamically find any model currently loaded in the GPU
            $ActiveModels = & ollama ps 2>$null | Select-Object -Skip 1 | ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ }
            
            if ($ActiveModels) {
                # Save the model names so we can optionally reload them later
                $ModelsToRestore = $ActiveModels
                foreach ($Model in $ActiveModels) {
                    Write-Host "Temporarily unloading Ollama model '$Model' to free up GPU..." -ForegroundColor Yellow
                    & ollama stop $Model | Out-Null
                }
                # Give the graphics card a brief moment to clear its cache
                Start-Sleep -Seconds 2
            } else {
                Write-Host "GPU is clear. No active Ollama models found in VRAM." -ForegroundColor Green
            }
        }
    } catch {
        # Continue
    }
}


Write-Host "========================  File processing finished  ========================`n" -ForegroundColor Green

