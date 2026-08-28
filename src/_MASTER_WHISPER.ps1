<#
.SYNOPSIS
    Master Whisper Script - Batch Transcription Orchestrator
.DESCRIPTION
    Scans an input folder for audio files (.m4a, .mp3, .flac, .mp4), extracts parameters 
    from filename convention (file_name.LL-X#.EXT), checks for existing transcripts / AI notes,
    and invokes the whisper-asr-service-docker engine for missing items.
.PARAMETER InputFolder
    Path to the directory containing audio recordings. Defaults to current directory.
.PARAMETER ConfigPath
    Optional path to configuration JSON file. Defaults to config/config.default.json.
#>

param(
    [string]$InputFolder = ".",
    [string]$ConfigPath = $null
)

# Load configuration if available
$Config = $null
$DefaultConfigPaths = @(
    $ConfigPath,
    (Join-Path $PSScriptRoot "..\config\config.default.json"),
    (Join-Path $PSScriptRoot "config\config.default.json"),
    (Join-Path (Get-Location) "config\config.default.json")
) | Where-Object { $_ -and (Test-Path $_) }

if ($DefaultConfigPaths.Count -gt 0) {
    try {
        $Config = Get-Content -Path $DefaultConfigPaths[0] -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Warning "Could not parse config file at $($DefaultConfigPaths[0]): $_"
    }
}

# Helper function to determine which MD files need generation
function Get-MissingMdFiles {
    param(
        [string]$BasePath  # Full path without extension, e.g., "C:\folder\filename"
    )
    
    $notesPath = "$BasePath.NOTES.md"
    $summaryPath = "$BasePath.SUMMARY.md"
    
    $notesMissing = -not (Test-Path $notesPath)
    $summaryMissing = -not (Test-Path $summaryPath)
    
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
    
    # Pattern: file_name.LL-X#.EXT where:
    # - LL = language code (2 letters, case-insensitive)
    # - X = profile letter (P=phone, M=meeting, D=distant)
    # - # = speaker number
    $Pattern = '^(.+)\.([A-Z]{2})-([PMD])(\d+)\.[^.]+$'
    
    if ($FileName -match $Pattern) {
        $LanguageCode = $matches[2].ToLower()  # Convert to lowercase: CS→cs, SK→sk, EN→en
        $ProfileLetter = $matches[3]
        $SpeakerNumber = [int]$matches[4]
        
        # Convert profile letter to full name
        $Profile = switch ($ProfileLetter) {
            'P' { "phone" }
            'M' { "meeting" }
            'D' { "distant" }
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
        }
    }
    
    # Default: no pattern match, use default profile with auto language detection
    $defaultProfile = if ($Config -and $Config.defaults.profile) { $Config.defaults.profile } else { "phone" }
    $defaultMinSpeakers = if ($Config -and $Config.defaults.min_speakers) { $Config.defaults.min_speakers } else { 2 }
    $defaultMaxSpeakers = if ($Config -and $Config.defaults.max_speakers) { $Config.defaults.max_speakers } else { 2 }

    return @{
        Profile     = $defaultProfile
        Language    = ""
        MinSpeakers = $defaultMinSpeakers
        MaxSpeakers = $defaultMaxSpeakers
    }
}

# Define supported audio extensions (m4a, mp3, flac, mp4)
$AudioExtensions = @(".m4a", ".flac", ".mp4", ".mp3")

Write-Host "=============== Master Whisper Script ===============" -ForegroundColor Cyan
Write-Host "Scanning folder: $InputFolder" -ForegroundColor Yellow

# Get files from top-level only (non-recursive) that need processing
$AudioFiles = @()

# Check for original audio files (.m4a, .flac, .mp4, .mp3)
$OriginalAudioFiles = Get-ChildItem -Path $InputFolder -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Extension.ToLower() -in $AudioExtensions
}

if (-not $OriginalAudioFiles) {
    $OriginalAudioFiles = @()
}

foreach ($File in $OriginalAudioFiles) {
    # Define processed file suffix patterns based on profile
    $ProcessedSuffixes = @("PHONE-NORM_HP-LW-SP-LN", "MEETING-NORM_HP-LW-DN", "DISTANT-NORM_HP-LP-AC-SN")
    
    # Check if this file needs processing (none of the processed transcript files exist)
    $NeedsProcessing = $true
    
    foreach ($suffix in $ProcessedSuffixes) {
        $ProcessedBaseName = "$($File.BaseName).$suffix"
        
        foreach ($ext in @('.json', '.txt', '.srt', '.tsv', '.vtt', '.md')) {
            $CheckPath = Join-Path $File.DirectoryName "$ProcessedBaseName$ext"
            
            if (Test-Path $CheckPath) {
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
    $_.Name -match '\.PHONE-NORM_|\.MEETING-NORM_|\.DISTANT-NORM_'
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
        } else {
            continue
        }
        
        # Check if any transcript exists for this processed file
        $HasTranscript = $false
        foreach ($ext in @('.json', '.txt', '.srt', '.tsv', '.vtt', '.md')) {
            $CheckPath = Join-Path $PFile.DirectoryName "$Base$ext"
            if (Test-Path $CheckPath) {
                $Content = Get-Content $CheckPath -Raw -ErrorAction SilentlyContinue
                if (-not [string]::IsNullOrEmpty($Content)) {
                    $HasTranscript = $true
                    break
                }
            }
        }
        
        if (-not $HasTranscript) {
            # Find the original audio file that would create this processed file
            $OriginalPath = $PFile.FullName -replace '\.PHONE-NORM_[^\.]+$' -replace '\.MEETING-NORM_[^\.]+$' -replace '\.DISTANT-NORM_[^\.]+$'
            if (Test-Path $OriginalPath) {
                $AudioFiles += (Get-ChildItem $OriginalPath)
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
        $CurrentFilePath = "$($File.DirectoryName)\$($File.BaseName)$ext"
        
        if (Test-Path $CurrentFilePath) {
            $Content = Get-Content $CurrentFilePath -Raw -ErrorAction SilentlyContinue
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
    $MdCheck = Get-MissingMdFiles -BasePath "$($File.DirectoryName)\$($File.BaseName)"
    
    # Determine if processing is needed
    $NeedsProcessing = $AnyNonMdMissingOrEmpty -or $MdCheck.NotesMissing -or $MdCheck.SummaryMissing
    
    if ($NeedsProcessing) {
        Write-Host "Transcript incomplete for $($File.Name) (missing or empty files detected) - starting file processing..." -ForegroundColor Yellow
        
        # Parse filename to extract parameters
        $Params = Parse-FileNameParameters -FileName $File.Name
        
        Write-Host "  Filename: $($File.Name)" -ForegroundColor Cyan
        
        # Report which files are missing
        $MissingFiles = @()
        if ($MdCheck.NotesMissing) { $MissingFiles += "NOTES.md" }
        if ($MdCheck.SummaryMissing) { $MissingFiles += "SUMMARY.md" }
        if ($AnyNonMdMissingOrEmpty) {
            foreach ($ext in $NonMdExtensions) {
                if (-not (Test-Path "$($File.DirectoryName)\$($File.BaseName)$ext")) {
                    $MissingFiles += "$ext"
                }
            }
        }
        Write-Host "  Missing files: $($MissingFiles -join ', ')" -ForegroundColor DarkYellow
        
        # Determine what to process based on what's missing
        if ($MdCheck.NotesMissing -and $MdCheck.SummaryMissing -and -not $AnyNonMdMissingOrEmpty) {
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
        
        # Add Language parameter only if it's not empty (to allow auto-detection)
        if ($Params.Language -ne "") {
            $InvokeParams['Language'] = $Params.Language
        }
        
        & $ScriptPath @InvokeParams
    } else {
        Write-Host "Skipping $($File.Name) - all required transcripts are present and non-empty." -ForegroundColor Yellow
    }
}

Write-Host "=============== FOLDER Processing Complete ===================" -ForegroundColor Green
