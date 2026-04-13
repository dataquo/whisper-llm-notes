<#

NOT WORKING! 


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


#>



param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,

    [Parameter(Mandatory=$false)]
    [string]$Language = "cs", # Defaulting to Czech based on your last run

    [Parameter(Mandatory=$false)]
    [ValidateSet("meeting", "phone", "distant")]
    [string]$Profile = "meeting"
)

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

# --- 3. Profile Configurations ---
$ProfileSettings = @{
    "meeting" = @{
        "diarize"        = "true"
        "vad_filter"     = "true"
        "vad_onset"      = "0.1"
        "vad_offset"     = "0.2"
        "initial_prompt" = "Toto je nahrávka z meetingu."
        "min_speakers"   = "2"        
        "temperature"    = "0.0"
    }
    "phone" = @{
        "diarize"        = "true"
        "vad_filter"     = "false" # Disabled to catch quiet phone voices
        "initial_prompt" = "Přepis nahrávky telefonického hovoru. Hlasy mohou být zkreslené."
        "temperature"    = "0.0"
    }
    "distant" = @{
        "diarize"        = "true"
        "vad_filter"     = "true"
        "vad_onset"      = "0.1"
        "initial_prompt" = "Nahrávka z dálky v místnosti."
        "temperature"    = "0.2"
    }
}

$Config = $ProfileSettings[$Profile]
$BaseName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
$OutputDir = [System.IO.Path]::GetDirectoryName($FilePath)
$FullBase = Join-Path $OutputDir $BaseName

if (-not (Test-Path $FilePath)) { Write-Error "File not found: $FilePath"; exit }

Write-Host "--- Starting Transcription ---" -ForegroundColor Cyan
Write-Host "Profile: $Profile | Language: $Language" -ForegroundColor Yellow

# Show initial progress state
Write-Progress -Activity "Processing Audio File" -Status "Starting transcription..." -PercentComplete 20

# Get file size for estimation (this helps us show a more meaningful progress bar)
$FileSize = (Get-Item $FilePath).Length
Write-Host "File Size: $([Math]::Round($FileSize/1MB, 2)) MB" -ForegroundColor Gray

# Show upload start state
Write-Progress -Activity "Processing Audio File" -Status "Uploading file..." -PercentComplete 30

# Requesting verbose_json to get segment data for SRT/VTT/TSV with proper quoting of path
<#
The endpoint you are using (/v1/audio/transcriptions) is the OpenAI-compatibility layer. While it is great for standard tools, 
it often ignores "extra" parameters like diarize because they aren't part of the official OpenAI spec.
#>
<#
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

# --- 4. API Call (Updated to Native Endpoint) ---
Write-Host "Sending request to Native WhisperX Endpoint..." -ForegroundColor Gray

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

# Note: The native endpoint uses 'audio_file' instead of 'file'

# Show processing state
Write-Progress -Activity "Processing Audio File" -Status "Processing transcription..." -PercentComplete 70

if ($LASTEXITCODE -ne 0 -or -not $Response) { 
    Write-Error "Transcription failed or API is offline.`nExit Code: $LASTEXITCODE`nResponse: $Response"
    exit 
}

# Convert raw string to PowerShell Object
$Data = $Response | ConvertFrom-Json

# Show generation state
Write-Progress -Activity "Processing Audio File" -Status "Generating output files..." -PercentComplete 75


# --- 5. Generate All 5 Formats (Updated with Speaker Labels) ---
Write-Host "Generating files with Speaker Labels..." -ForegroundColor Gray

# 1. JSON (Already contains speaker data)
Write-Progress -Activity "Processing generated JSON File" -Status "Generating output files..." -PercentComplete 80

Save-Utf8 "$FullBase.json" $Response

Start-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formats


# 2. TXT (Rebuilt from segments to include speakers)
Write-Progress -Activity "Generating TXT File with different speakers" -Status "Generating output files..." -PercentComplete 85

$txt = ""
foreach ($s in $Data.segments) {
    $speakerPrefix = if ($s.speaker) { "[$($s.speaker)]: " } else { "" }
    $txt += "$speakerPrefix$($s.text.Trim())`r`n"
}
Save-Utf8 "$FullBase.txt" $txt

Start-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formats



# 3. SRT
Write-Progress -Activity "Generating SRT File with different speakers" -Status "Generating output files..." -PercentComplete 90

$srt = ""
for ($i=0; $i -lt $Data.segments.Count; $i++) {
    $s = $Data.segments[$i]
    $speakerPrefix = if ($s.speaker) { "[$($s.speaker)] " } else { "" }
    $srt += "$($i+1)`r`n"
    $srt += "$(Format-Time $s.start) --> $(Format-Time $s.end)`r`n"
    $srt += "$speakerPrefix$($s.text.Trim())`r`n`r`n"
}
Save-Utf8 "$FullBase.srt" $srt

Start-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formats


# 4. VTT
Write-Progress -Activity "Generating VTT File with different speakers" -Status "Generating output files..." -PercentComplete 95

$vtt = "WEBVTT`r`n`r`n"
foreach ($s in $Data.segments) {
    $speakerPrefix = if ($s.speaker) { "[$($s.speaker)] " } else { "" }
    $vtt += "$(Format-Time $s.start '.') --> $(Format-Time $s.end '.')`r`n"
    $vtt += "$speakerPrefix$($s.text.Trim())`r`n`r`n"
}
Save-Utf8 "$FullBase.vtt" $vtt

Start-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formats



# 5. TSV
Write-Progress -Activity "Generating VTT File with different speakers" -Status "Generating output files..." -PercentComplete 99

$tsv = "start`tend`tspeaker`ttext`r`n"
foreach ($s in $Data.segments) {
    $tsv += "$($s.start)`t$($s.end)`t$($s.speaker)`t$($s.text.Trim())`r`n"
}
Save-Utf8 "$FullBase.tsv" $tsv

Start-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formatsStart-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formats

# Final completion state
Write-Progress -Activity "Processing Audio File" -Status "Completed!" -PercentComplete 100 -Completed

Write-Host "Success! All files created in: $OutputDir" -ForegroundColor Green

# --- 6. Automate the Container Restart--


Write-Host "Flushing GPU VRAM by restarting Docker container..." -ForegroundColor DarkYellow
docker restart whisperx-api | Out-Null
Start-Sleep -Seconds 10 # Give the API a few seconds to boot back up for the next run
Write-Host "Ready for next file." -ForegroundColor Green