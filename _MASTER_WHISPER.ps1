# Master Whisper Script - Batch Transcription Orchestrator
# Scans input folder for audio files and transcribes those without existing transcripts
# 
# ===========================================================================
# CHANGELOG
# ===========================================================================
# v03.00 (2026-04-22): 
#   - Updated to check for processed files with suffix pattern (*.PHONE-NORM_*.txt, etc.)
#   - Fixed file path handling with special characters using proper .NET methods
#   - Added support for all profiles: phone, meeting, distant
# 
# v02.00 (2026-04-14): 
#   - Extended file checking to include ALL transcript formats: .json, .txt, .srt, .tsv, .vtt, .md
#   - Added empty file detection using Get-Content and [string]::IsNullOrEmpty()
#   - Script now triggers whisper-asr-service-docker.v04.02.ps1 if ANY transcript file is missing or empty
# 
# v01.00: Initial version (checks only .md files)


param(
    [string]$InputFolder = "."  # Default to current directory
)

# Define supported audio extensions (m4a, mp3, flac only as requested)
$AudioExtensions = @(".m4a", ".flac", ".mp4")

Write-Host "=============== Master Whisper Script ===============" -ForegroundColor Cyan
Write-Host "Scanning folder: $InputFolder" -ForegroundColor Yellow


# Get files from top-level only (non-recursive) that need processing
$AudioFiles = @()

# Check for original audio files (.m4a, .flac, .mp4)
$OriginalAudioFiles = Get-ChildItem -Path $InputFolder -File | Where-Object {
    $_.Extension -in $AudioExtensions
}

foreach ($File in $OriginalAudioFiles) {
    # Define processed file suffix patterns based on profile
    $ProcessedSuffixes = @("PHONE-NORM_HP-LW-SP-LN", "MEETING-NORM_HP-LW-DN", "DISTANT-NORM_HP-LP-AC-SN")
    
    # Check if this file needs processing (none of the processed transcript files exist)
    $NeedsProcessing = $true
    
    foreach ($suffix in $ProcessedSuffixes) {
        $ProcessedBaseName = "$($File.BaseName).$suffix"
        
        foreach ($ext in @('.json', '.txt', '.srt', '.tsv', '.vtt', '.md')) {
            $CheckPath = Join-Path $File.Directory "$ProcessedBaseName$ext"
            
            if (Test-Path $CheckPath) {
                $NeedsProcessing = $false
                break
            }
        }
        
        if (!$NeedsProcessing) { break }
    }
    
    if ($NeedsProcessing) {
        $AudioFiles += $File
    }
}

# Also check for processed files that might exist without their transcripts
$ProcessedFiles = Get-ChildItem -Path $InputFolder -File | Where-Object {
    $_.Name -match '\.PHONE-NORM_|\.MEETING-NORM_|\.DISTANT-NORM_'
} | ForEach-Object {
    # Extract the base name without suffix
    if ($_.Name -match '^(.+)\.PHONE-NORM_[^\.]+$') {
        $Base = $matches[1]
    } elseif ($_.Name -match '^(.+)\.MEETING-NORM_[^\.]+$') {
        $Base = $matches[1]
    } elseif ($_.Name -match '^(.+)\.DISTANT-NORM_[^\.]+$') {
        $Base = $matches[1]
    } else {
        return $_
    }
    
    # Check if any transcript exists for this processed file
    $HasTranscript = $false
    foreach ($ext in @('.json', '.txt', '.srt', '.tsv', '.vtt', '.md')) {
        $CheckPath = Join-Path $_.Directory "$Base$ext"
        if (Test-Path $CheckPath) {
            $Content = Get-Content $CheckPath -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrEmpty($Content)) {
                $HasTranscript = $true
                break
            }
        }
    }
    
    if (!$HasTranscript) {
        # Find the original audio file that would create this processed file
        $OriginalPath = $_.FullName -replace '\.PHONE-NORM_[^\.]+$' -replace '\.MEETING-NORM_[^\.]+$' -replace '\.DISTANT-NORM_[^\.]+$'
        if (Test-Path $OriginalPath) {
            $AudioFiles += (Get-ChildItem $OriginalPath)
        }
    }
}

# Remove duplicates
$AudioFiles = $AudioFiles | Select-Object -Unique

Write-Host "Found $($AudioFiles.Count) audio file(s) to process." -ForegroundColor Green

if ($AudioFiles.Count -eq 0) {
    Write-Host "No audio files found in $InputFolder" -ForegroundColor Gray
    exit 0
}

Write-Host "Found $($AudioFiles.Count) audio file(s) to process." -ForegroundColor Green


# Process each audio file
foreach ($File in $AudioFiles) {
    # Define all transcript extensions to check (json, txt, srt, tsv, vtt, md)
    $TranscriptExtensions = @('.json', '.txt', '.srt', '.tsv', '.vtt', '.md')
    
    # Check if ANY transcript file is missing or empty - trigger processing in that case
    $AnyFileMissingOrEmpty = $false
    
    foreach ($ext in $TranscriptExtensions) {
        $CurrentFilePath = "$($File.DirectoryName)\$($File.BaseName)$ext"
        
        if (Test-Path $CurrentFilePath) {
            $Content = Get-Content $CurrentFilePath -Raw -ErrorAction SilentlyContinue
            
            if ([string]::IsNullOrEmpty($Content)) {
                # Found an empty file, so we should trigger processing
                $AnyFileMissingOrEmpty = $true
                Write-Host "  Warning: File exists but is empty: $($CurrentFilePath)" -ForegroundColor DarkYellow
                break
            }
        } else {
            # File doesn't exist, so we should trigger processing
            $AnyFileMissingOrEmpty = $true
            break
        }
    }
    
    if ($AnyFileMissingOrEmpty) {
        Write-Host "Transcript incomplete for $($File.Name) (missing or empty files detected) - starting file processing..." -ForegroundColor Yellow 
        # Call whisper-asr-service-docker.ps1 with:
        # - FilePath: full path to audio file
        # - Profile: "phone" (default as specified)
        # - Language: omitted entirely (detected by whisper automatically based on first 30 seconds of audio)
        
        # Use explicit script invocation with proper quoting for special characters in paths
        $ScriptPath = Join-Path $PSScriptRoot "whisper-asr-service-docker.v05.00.ps1"
        & $ScriptPath -FilePath "$($File.FullName)" -Profile "phone"
    } else {
        Write-Host "Skipping $($File.Name) - all required transcripts are present and non-empty." -ForegroundColor Yellow
    }
}


Write-Host "=============== FOLDER Processing Complete ===================" -ForegroundColor Green