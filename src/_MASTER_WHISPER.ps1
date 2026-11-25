<#
.SYNOPSIS
    Master Whisper Script - Batch Transcription & AI Summarization Orchestrator.

.DESCRIPTION
    Scans an input directory for audio recordings (.m4a, .mp3, .flac, .mp4), extracts ASR and
    diarization parameters from the filename tag convention, checks for missing transcript or AI
    summary files (.json, .txt, .srt, .tsv, .vtt, .NOTES.md, .SUMMARY.md), and invokes the
    whisper-asr-service-docker execution engine.

    -----------------------------------------------------------------------------
    FILENAME-BASED PARAMETER CONVENTION:  [name].[LL]-[X][#].[ext]
    -----------------------------------------------------------------------------
    The orchestrator automatically extracts transcription settings from the filename:

      * [LL] - Language Code (case-insensitive, 2 letters):
          - SK : Slovak (targets fine-tuned Slovak models where configured)
          - CS : Czech (uses multilingual large-v3)
          - EN : English (uses multilingual large-v3)
          - (omitted or untagged) : Whisper automatic language detection

      * [X] - Digital Signal Processing (DSP) Profile Letter:
          - P : Phone   (PHONE-NORM: High-Pass 200Hz, Low-Pass 3500Hz, Voice Leveler, 1.5s Lead-in Priming, -16 LUFS)
          - M : Meeting (HP-LW-DN: High-Pass 80Hz, Light Denoise, -16 LUFS)
          - D : Distant (HP-LP-AC-SN: High-Pass 100Hz, Low-Pass 6000Hz, Dynamic Gate, -16 LUFS)
          - H : Hallway (HP-LP-DN-EQ: High-Pass 220Hz, Low-Pass 3700Hz, Notch EQ, -16 LUFS)
          - E : Echoed  (ECHOED-NORM: Echo suppression, Notch 380Hz + Greedy beam_size=1 decoding)

      * [#] - Speaker Count for Diarization (1-9):
          - Sets both min_speakers and max_speakers to this exact count.
          - Example: '2' sets min_speakers=2, max_speakers=2.

      * Untagged Files (e.g., 'recording.m4a'):
          - Defaults to Phone profile (P), auto-detect language, min_speakers=2, max_speakers=2.

    FILENAME EXAMPLES:
      meeting_sync.SK-M4.mp3    -> Slovak, Meeting profile, 4 speakers
      client_call.CS-P2.m4a     -> Czech, Phone profile, 2 speakers
      cctv_corridor.SK-E2.mp4   -> Slovak, Echoed profile, 2 speakers
      hall_lecture.EN-D1.flac   -> English, Distant profile, 1 speaker
      voice_note.m4a            -> Default: Phone profile, Auto language, 2 speakers

    -----------------------------------------------------------------------------
    PRE-PROCESSING / EXTERNAL INTEGRATIONS:
    -----------------------------------------------------------------------------
    Before audio scanning and transcription, the orchestrator checks for the DJI video
    conversion script ('..\DJI\convert_DJI_videos_with_MetaData.ps1'). If present, it invokes
    it with hardware-optimized profile ('special-quality-hw-opt-Apple_M2' on macOS with
    VideoToolbox or 'special-quality-hw-dec-cuda' on Windows with Nvidia CUDA) and silence
    detection disabled ('0') on the target input directory to transcode DJI recordings with
    metadata prior to ASR. Custom scenes can be passed via -DjiScene, or bypassed with -SkipDJI.

.PARAMETER InputFolder
    Path to the directory containing audio recordings. Defaults to '.' (current working directory).

.PARAMETER ConfigPath
    Optional explicit path to a custom configuration JSON file, overriding layered defaults.

.PARAMETER DisableLLM
    When specified (aliases: -DisableLLMs, -SkipLLM, -NoLLM), skips all LLM summarization
    (both Ollama and LM Studio). Generates only raw WhisperX ASR transcript files.

.PARAMETER OnlyOllama
    When specified (aliases: -OnlyOlama, -OllamaOnly), generates ONLY Ollama executive
    summaries (.SUMMARY.md) and skips LM Studio detailed notes.

.PARAMETER OnlyLMStudio
    When specified (aliases: -LMStudioOnly, -OnlyLM), generates ONLY LM Studio structured
    meeting notes (.NOTES.md) and skips Ollama executive summaries.

.PARAMETER SkipDJI
    When specified (aliases: -NoDJI, -SkipDJIConversion), skips the preliminary DJI video
    conversion step (..\DJI\convert_DJI_videos_with_MetaData.ps1) and proceeds directly to
    audio scanning and transcription.

.PARAMETER DjiScriptPath
    Optional explicit path to the DJI video conversion script (convert_DJI_videos_with_MetaData.ps1).
    Defaults to candidate resolution at '..\DJI\convert_DJI_videos_with_MetaData.ps1'.

.PARAMETER DjiScene
    Optional explicit conversion profile/scene for the DJI video conversion script
    (e.g., 'special-quality-hw-opt-Apple_M2', 'special-quality-hw-dec-cuda', 'day', 'night').
    Defaults dynamically to 'special-quality-hw-opt-Apple_M2' on macOS and 'special-quality-hw-dec-cuda' on Windows.

.EXAMPLE
    .\_MASTER_WHISPER.ps1 -InputFolder "D:\Recordings"
    Scans 'D:\Recordings', executes DJI video conversion if script is present, and runs full pipeline (ASR + LM Studio notes + Ollama summary) for all pending files.

.EXAMPLE
    .\_MASTER_WHISPER.ps1 -InputFolder "D:\Recordings" -SkipDJI
    Scans 'D:\Recordings' and transcribes audio, skipping the preliminary DJI video conversion step.

.EXAMPLE
    .\_MASTER_WHISPER.ps1 -OnlyOllama
    Scans current folder and generates only missing Ollama executive summaries (.SUMMARY.md).

.EXAMPLE
    .\_MASTER_WHISPER.ps1 -OnlyLMStudio
    Scans current folder and generates only missing LM Studio structured notes (.NOTES.md).

.EXAMPLE
    .\_MASTER_WHISPER.ps1 -DisableLLM
    Performs only WhisperX audio transcription and secondary formats, bypassing LLM processing.

.NOTES
    Version: v07.02
    - Dynamic Cross-Platform DJI Scene Resolution: Automatically defaults to 'special-quality-hw-opt-Apple_M2' (VideoToolbox) on macOS and 'special-quality-hw-dec-cuda' (CUDA) on Windows, with -DjiScene CLI override.
    - Anti-Hallucination ASR Decoding Invariant: Configured condition_on_previous_text=false across meeting profile and execution pipeline to eliminate runaway "Thank you." hallucination loops on silent screen captures and muted recordings.
    - UNC Network Share Forward-Slash Normalization: Resolves curl exit code 26 on Windows by normalizing SMB paths (\\truenas\... -> //truenas/...) preventing quote-escaping corruption.
    - FFmpeg Demuxer Resilience & Video Bypass: Execution engine incorporates -vn and -err_detect ignore_err -fflags +genpts+igndts+discardcorrupt to safely handle corrupted/truncated cutfiles and accelerate audio preprocessing.
    - Cross-Platform macOS Apple Silicon (M2 Max) Support: Enables native batch orchestration and engine delegation across Windows 11 and macOS pwsh environments.
    - Path Standardization: Enforced Join-Path across all transcript checks, missing file evaluation, and candidate resolution to prevent literal backslash artifacts on Unix systems.
    - Integrated external DJI video conversion invocation (..\DJI\convert_DJI_videos_with_MetaData.ps1) using profile 'special-quality-hw-dec-cuda' without audio silence detection.
    - Added -SkipDJI and -DjiScriptPath parameters for flexible external video transcoding orchestration.
    - Added duplicate suppression for converted DJI WebM files (*.CRF-*_LIBSVT-AV1*.webm) when original source media exists.
    - Enhanced Parse-FileNameParameters to strip video conversion suffixes (.CRF-44_LIBSVT-AV1...) ensuring reliable tag extraction.
    - High-visibility untagged profile alerts in bright red notifying users when recordings lack .LL-X# tagging.
    - Zero-speech resilience allowing blank transcripts to be safely generated without crashing pipeline batch loops.
    - Universal -LiteralPath enforcement across all filesystem cmdlets (Test-Path, Get-Content, Get-Item) to handle bracketed [ ] filenames without wildcard globbing failures.
    - Re-calibrated Phone profile (P) to distinct narrowband bandpass (200-3500Hz) with voice leveler and 1.5s lead-in silence priming.
    - Integrated automatic sub-second timestamp compensation in execution engine.
    - Enriched Comment-Based Help with comprehensive Filename Parameter Convention, profile details, and .EXAMPLE blocks.
    - Native PowerShell Get-Help, -Examples, and -? parameter discovery integration.
    - Added -OnlyOllama and -OnlyLMStudio switch parameters for selective LLM generation.
    - Fully dynamic profile and suffix resolution from layered AppConfig.
    - Pure batch orchestrator decoupled from Docker lifecycle and FFmpeg DSP.
#>

param(
    [string]$InputFolder = ".",
    [string]$ConfigPath = $null,
    [Alias("DisableLLMs", "SkipLLM", "NoLLM")]
    [switch]$DisableLLM,
    [Alias("OnlyOlama", "OllamaOnly")]
    [switch]$OnlyOllama,
    [Alias("LMStudioOnly", "OnlyLM")]
    [switch]$OnlyLMStudio,
    [Alias("NoDJI", "SkipDJIConversion")]
    [switch]$SkipDJI,
    [string]$DjiScriptPath = $null,
    [Alias("DjiProfile")]
    [string]$DjiScene = $null
)

# Helper function to determine which MD files need generation
function Get-MissingMdFiles {
    param(
        [string]$BasePath,  # Full path without extension, e.g., "C:\folder\filename"
        [switch]$OnlyOllama,
        [switch]$OnlyLMStudio
    )
    
    $notesPath = "$BasePath.NOTES.md"
    $summaryPath = "$BasePath.SUMMARY.md"
    
    $notesMissing = -not (Test-Path -LiteralPath $notesPath)
    $summaryMissing = -not (Test-Path -LiteralPath $summaryPath)
    
    if ($OnlyOllama) {
        $generateMode = if ($summaryMissing) { "summary" } else { "none" }
        return @{
            NotesMissing   = $false
            SummaryMissing = $summaryMissing
            GenerateMode   = $generateMode
        }
    } elseif ($OnlyLMStudio) {
        $generateMode = if ($notesMissing) { "notes" } else { "none" }
        return @{
            NotesMissing   = $notesMissing
            SummaryMissing = $false
            GenerateMode   = $generateMode
        }
    }
    
    $generateMode = if ($notesMissing -and $summaryMissing) { 
        "both" 
    } elseif ($notesMissing) { 
        "notes" 
    } elseif ($summaryMissing) {
        "summary"
    } else {
        "none"
    }
    
    return @{
        NotesMissing   = $notesMissing
        SummaryMissing = $summaryMissing
        GenerateMode   = $generateMode
    }
}

# Function to parse filename and extract language/profile/speaker parameters
function Parse-FileNameParameters {
    param([string]$FileName)
    
    # Strip any DJI video conversion suffixes (e.g., .CRF-44_LIBSVT-AV1...) before checking tag pattern
    $EffectiveFileName = $FileName -replace '(\.CRF-\d+|_CRF\d+|[\._]LIBSVT-AV1)[^\.]*(\.[^.]+)$', '$2'
    
    # Pattern: file_name.LL-X#.EXT where:
    # - LL = language code (2 letters, case-insensitive)
    # - X = profile letter (P=phone, M=meeting, D=distant, H=hallway, E=echoed)
    # - # = speaker number
    $Pattern = '^(.+)\.([A-Z]{2})-([PMDHE])(\d+)\.[^.]+$'
    
    if ($EffectiveFileName -match $Pattern) {
        $LanguageCode = $matches[2].ToLower()  # Convert to lowercase: CS→cs, SK→sk, EN→en
        $ProfileLetter = $matches[3]
        $SpeakerNumber = [int]$matches[4]
        
        # Convert profile letter to full name
        $Profile = switch ($ProfileLetter) {
            'P' { "phone" }
            'M' { "meeting" }
            'D' { "distant" }
            'H' { "hallway" }
            'E' { "echoed" }
            default { "phone" }
        }
        
        # Convert language code
        $Language = switch ($LanguageCode) {
            'cs' { "cs" }
            'sk' { "sk" }
            'en' { "en" }
            default { "" }  # Empty means auto-detect by Whisper
        }
        
        return @{
            Profile     = $Profile
            Language    = $Language
            MinSpeakers = $SpeakerNumber
            MaxSpeakers = $SpeakerNumber
            IsDefault   = $false
        }
    }
    
    # Default: no pattern match, use default profile with auto language detection
    return @{
        Profile     = "phone"
        Language    = ""
        MinSpeakers = 2
        MaxSpeakers = 2
        IsDefault   = $true
    }
}

# Helper function to locate DJI video conversion script
function Get-DjiScriptPath {
    param(
        [string]$ExplicitPath = $null
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if (Test-Path -LiteralPath $ExplicitPath) {
            return (Get-Item -LiteralPath $ExplicitPath).FullName
        }
        return $null
    }

    $candidatePaths = @()
    if ($PSScriptRoot) {
        $candidatePaths += (Join-Path (Split-Path $PSScriptRoot -Parent) "..\DJI\convert_DJI_videos_with_MetaData.ps1")
        $candidatePaths += (Join-Path $PSScriptRoot "..\..\DJI\convert_DJI_videos_with_MetaData.ps1")
    }
    $candidatePaths += (Join-Path (Get-Location) "..\DJI\convert_DJI_videos_with_MetaData.ps1")
    $candidatePaths += "..\DJI\convert_DJI_videos_with_MetaData.ps1"

    foreach ($cand in $candidatePaths) {
        if (Test-Path -LiteralPath $cand) {
            return (Get-Item -LiteralPath $cand).FullName
        }
    }

    return $null
}

# Helper function to invoke DJI video conversion
function Invoke-DjiConversion {
    param(
        [string]$TargetFolder,
        [string]$ExplicitScriptPath = $null,
        [string]$Scene = $null,
        [switch]$Skip
    )

    if ($Skip) {
        Write-Host "DJI video conversion skipped (-SkipDJI specified)." -ForegroundColor DarkGray
        return $false
    }

    $resolvedScript = Get-DjiScriptPath -ExplicitPath $ExplicitScriptPath
    if (-not $resolvedScript) {
        if (-not [string]::IsNullOrWhiteSpace($ExplicitScriptPath)) {
            Write-Warning "Specified DJI script path was not found: $ExplicitScriptPath"
        } else {
            Write-Host "DJI video conversion script not found at ..\DJI\convert_DJI_videos_with_MetaData.ps1 - skipping conversion." -ForegroundColor DarkGray
        }
        return $false
    }

    $resolvedFolder = if (Test-Path -LiteralPath $TargetFolder) {
        (Convert-Path -LiteralPath $TargetFolder)
    } else {
        $TargetFolder
    }

    $resolvedScene = if (-not [string]::IsNullOrWhiteSpace($Scene)) {
        $Scene
    } elseif ($IsMacOS) {
        "special-quality-hw-opt-Apple_M2"
    } else {
        "special-quality-hw-dec-cuda"
    }

    Write-Host "================ DJI Video Conversion ================" -ForegroundColor Cyan
    Write-Host "Invoking: $resolvedScript" -ForegroundColor Gray
    Write-Host "Source Folder: $resolvedFolder" -ForegroundColor Gray
    Write-Host "Profile (Scene): $resolvedScene" -ForegroundColor Gray
    Write-Host "Audio Silence Detection: disabled (0)" -ForegroundColor Gray

    try {
        & $resolvedScript -sourceFolder $resolvedFolder -scene $resolvedScene -checkAudioSilence "0"
        Write-Host "--- DJI Video Conversion Complete ---" -ForegroundColor Cyan
        return $true
    } catch {
        Write-Error "Error during DJI video conversion: $_"
        return $false
    }
}

# Define supported audio extensions (m4a, mp3, flac, mp4, webm)
$AudioExtensions = @(".m4a", ".flac", ".mp4", ".mp3", ".webm")

Write-Host "=============== Master Whisper Script ===============" -ForegroundColor Cyan
Write-Host "Scanning folder: $InputFolder" -ForegroundColor Yellow

# Step 1: Pre-process DJI videos with external script if available
Invoke-DjiConversion -TargetFolder $InputFolder -ExplicitScriptPath $DjiScriptPath -Scene $DjiScene -Skip:$SkipDJI

# Step 2: Get files from top-level only (non-recursive) that need processing
$AudioFiles = @()

# Check for original audio files (.m4a, .flac, .mp4, .mp3, .webm), excluding normalized intermediate files
# and duplicate converted DJI WebM files when original source media is present
$OriginalAudioFiles = Get-ChildItem -Path $InputFolder -File -ErrorAction SilentlyContinue | Where-Object {
    if ($_.Extension.ToLower() -notin $AudioExtensions) { return $false }
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
        if ($hasOriginalMedia) { return $false }
    }

    return $true
}

if (-not $OriginalAudioFiles) {
    $OriginalAudioFiles = @()
}

foreach ($File in $OriginalAudioFiles) {
    # Define processed file suffix patterns based on profile
    $ProcessedSuffixes = @("PHONE-NORM_HP-LW-SP-LN", "MEETING-NORM_HP-LW-DN", "DISTANT-NORM_HP-LP-AC-SN", "HALLWAY-NORM_HP-LP-DN-EQ", "HALLWAY-NORM_HP-LP-GT-SN", "HALLWAY-NORM_HP-LP-DN", "ECHOED-NORM_HP-LP-DN-EQ", "ECHOED-NORM_WP-HP-LP-DN-EQ")
    
    # Check if this file needs processing (none of the processed transcript files exist)
    $NeedsProcessing = $true
    
    foreach ($suffix in $ProcessedSuffixes) {
        $ProcessedBaseName = "$($File.BaseName).$suffix"
        
        foreach ($ext in @('.json', '.txt', '.srt', '.tsv', '.vtt', '.md')) {
            $CheckPath = Join-Path $File.DirectoryName "$ProcessedBaseName$ext"
            
            if (Test-Path -LiteralPath $CheckPath) {
                $NeedsProcessing = $false
                break
            }
        }
        
        if (-not $NeedsProcessing) { break }
    }
    
    if ($NeedsProcessing) {
        $AudioFiles += $File
    }
}

# Also check for processed files that might exist without their transcripts
$ProcessedFiles = Get-ChildItem -Path $InputFolder -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '\.PHONE-NORM_|\.MEETING-NORM_|\.DISTANT-NORM_|\.HALLWAY-NORM_'
}

if ($ProcessedFiles) {
    foreach ($PFile in $ProcessedFiles) {
        # Extract the base name without suffix
        if ($PFile.Name -match '^(.+)\.PHONE-NORM_[^\.]+$') {
            $Base = $matches[1]
        } elseif ($PFile.Name -match '^(.+)\.MEETING-NORM_[^\.]+$') {
            $Base = $matches[1]
        } elseif ($PFile.Name -match '^(.+)\.DISTANT-NORM_[^\.]+$') {
            $Base = $matches[1]
        } elseif ($PFile.Name -match '^(.+)\.HALLWAY-NORM_[^\.]+$') {
            $Base = $matches[1]
        } else {
            continue
        }
        
        # Check if any transcript exists for this processed file
        $HasTranscript = $false
        foreach ($ext in @('.json', '.txt', '.srt', '.tsv', '.vtt', '.md')) {
            $CheckPath = Join-Path $PFile.DirectoryName "$Base$ext"
            if (Test-Path -LiteralPath $CheckPath) {
                $Content = Get-Content -LiteralPath $CheckPath -Raw -ErrorAction SilentlyContinue
                if (-not [string]::IsNullOrEmpty($Content)) {
                    $HasTranscript = $true
                    break
                }
            }
        }
        
        if (-not $HasTranscript) {
            # Find the original audio file that would create this processed file
            $OriginalPath = $PFile.FullName -replace '\.PHONE-NORM_[^\.]+$' -replace '\.MEETING-NORM_[^\.]+$' -replace '\.DISTANT-NORM_[^\.]+$' -replace '\.HALLWAY-NORM_[^\.]+$'
            if (Test-Path -LiteralPath $OriginalPath) {
                $AudioFiles += (Get-Item -LiteralPath $OriginalPath -ErrorAction SilentlyContinue)
            }
        }
    }
}

# Remove duplicates
$AudioFiles = $AudioFiles | Select-Object -Unique

Write-Host "Found $($AudioFiles.Count) audio file(s) to process." -ForegroundColor Green

if ($AudioFiles.Count -eq 0) {
    Write-Host "No pending audio files found in $InputFolder" -ForegroundColor Gray
    return
}

# Locate whisper engine script
$ScriptPath = Join-Path $PSScriptRoot "whisper-asr-service-docker.ps1"
if (-not (Test-Path $ScriptPath)) {
    # Fallback search paths
    $CandidatePaths = @(
        (Join-Path (Get-Location) "src\whisper-asr-service-docker.ps1"),
        (Join-Path (Get-Location) "whisper-asr-service-docker.ps1")
    )
    foreach ($cand in $CandidatePaths) {
        if (Test-Path $cand) {
            $ScriptPath = $cand
            break
        }
    }
}

if (-not (Test-Path $ScriptPath)) {
    Write-Error "Could not find whisper-asr-service-docker.ps1 at $ScriptPath"
    return
}

# Process each audio file
foreach ($File in $AudioFiles) {
    # Define all transcript extensions to check (json, txt, srt, tsv, vtt)
    $NonMdExtensions = @('.json', '.txt', '.srt', '.tsv', '.vtt')
    
    # Check if ANY non-MD transcript file is missing or empty
    $AnyNonMdMissingOrEmpty = $false
    foreach ($ext in $NonMdExtensions) {
        $CurrentFilePath = Join-Path $File.DirectoryName "$($File.BaseName)$ext"
        
        if (Test-Path -LiteralPath $CurrentFilePath) {
            $Content = Get-Content -LiteralPath $CurrentFilePath -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrEmpty($Content)) {
                $AnyNonMdMissingOrEmpty = $true
                Write-Host "  Warning: File exists but is empty: $($CurrentFilePath)" -ForegroundColor DarkYellow
                break
            }
        } else {
            $AnyNonMdMissingOrEmpty = $true
            break
        }
    }
    
    # Check which MD files are missing (NOTES.md and SUMMARY.md)
    $TargetBasePath = Join-Path $File.DirectoryName $File.BaseName
    $MdCheck = Get-MissingMdFiles -BasePath $TargetBasePath -OnlyOllama:$OnlyOllama -OnlyLMStudio:$OnlyLMStudio
    
    # Determine if processing is needed
    $NeedsProcessing = if ($DisableLLM) {
        $AnyNonMdMissingOrEmpty
    } else {
        $AnyNonMdMissingOrEmpty -or $MdCheck.NotesMissing -or $MdCheck.SummaryMissing
    }
    
    if ($NeedsProcessing) {
        Write-Host "Transcript incomplete for $($File.Name) (missing or empty files detected) - starting file processing..." -ForegroundColor Yellow
        
        # Parse filename to extract parameters
        $Params = Parse-FileNameParameters -FileName $File.Name
        
        Write-Host "  Filename: $($File.Name)" -ForegroundColor Cyan
        if ($Params.IsDefault) {
            Write-Host "  WARNING: No profile tag defined in filename '$($File.Name)'. Using default profile '$($Params.Profile)' with auto-detection. Recommended: tag filename as [name].[LL]-[X][#].[ext] (e.g. .SK-M2, .CS-P2, .EN-D1)." -ForegroundColor Red
        }
        
        # Report which files are missing
        $MissingFiles = @()
        if (-not $DisableLLM -and $MdCheck.NotesMissing) { $MissingFiles += "NOTES.md" }
        if (-not $DisableLLM -and $MdCheck.SummaryMissing) { $MissingFiles += "SUMMARY.md" }
        if ($AnyNonMdMissingOrEmpty) {
            foreach ($ext in $NonMdExtensions) {
                $checkExtPath = Join-Path $File.DirectoryName "$($File.BaseName)$ext"
                if (-not (Test-Path -LiteralPath $checkExtPath)) {
                    $MissingFiles += "$ext"
                }
            }
        }
        Write-Host "  Missing files: $($MissingFiles -join ', ')" -ForegroundColor DarkYellow
        
        # Determine what to process based on what's missing
        if ($DisableLLM) {
            $GenerateMode = "none"
        } elseif ($OnlyOllama) {
            $GenerateMode = "summary"
        } elseif ($OnlyLMStudio) {
            $GenerateMode = "notes"
        } elseif ($MdCheck.NotesMissing -and $MdCheck.SummaryMissing -and -not $AnyNonMdMissingOrEmpty) {
            # Only MD files missing, no non-MD files missing - generate only MD files
            $GenerateMode = $MdCheck.GenerateMode
        } elseif ($AnyNonMdMissingOrEmpty) {
            # Non-MD files missing - need full transcription, then generate missing MD files
            $GenerateMode = $MdCheck.GenerateMode
        } else {
            # Fallback: generate both
            $GenerateMode = "both"
        }
        
        # Build parameters hashtable
        $InvokeParams = @{
            'FilePath'     = "$($File.FullName)"
            'Profile'      = $Params.Profile
            'GenerateMode' = $GenerateMode
        }
        
        if ($DisableLLM) {
            $InvokeParams['DisableLLM'] = $true
        }

        if ($ConfigPath) {
            $InvokeParams['ConfigPath'] = $ConfigPath
        }
        
        # Add Language parameter only if it's not empty (to allow auto-detection)
        if ($Params.Language -ne "") {
            $InvokeParams['Language'] = $Params.Language
        }
        
        try {
            & $ScriptPath @InvokeParams
        } catch {
            Write-Error "Error processing $($File.Name): $_"
        }
    } else {
        Write-Host "Skipping $($File.Name) - all required transcripts are present and non-empty." -ForegroundColor Yellow
    }
}

Write-Host "=============== FOLDER Processing Complete ===================" -ForegroundColor Green
