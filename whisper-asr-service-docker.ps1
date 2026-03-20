
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
        "vad_onset"      = "0.2"
        "vad_offset"     = "0.2"
        "initial_prompt" = "Toto je nahrávka z meetingu."
        "temperature"    = "0.0"
    }
    "phone" = @{
        "diarize"        = "true"
        "vad_filter"     = "false" # Disabled to catch quiet phone voices
        "initial_prompt" = "Přepis nahrávky telefonického hovoru. Hlasy mohou být zkreslené."
        "temperature"    = "0.0"
    }
    "distant" = @{
        "diarize"        = "false"
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

# --- 4. API Call ---
# Requesting verbose_json to get segment data for SRT/VTT/TSV
$Response = & curl.exe -s -X POST "http://localhost:9000/v1/audio/transcriptions" `
  -H "Content-Type: multipart/form-data" `
  -F "file=@$FilePath" `
  -F "model=whisper-1" `
  -F "language=$Language" `
  -F "initial_prompt=$($Config.initial_prompt)" `
  -F "diarize=$($Config.diarize)" `
  -F "vad_filter=$($Config.vad_filter)" `
  -F "vad_onset=$($Config.vad_onset)" `
  -F "vad_offset=$($Config.vad_offset)" `
  -F "temperature=$($Config.temperature)" `
  -F "response_format=verbose_json"

if ($LASTEXITCODE -ne 0 -or -not $Response) { 
    Write-Error "Transcription failed or API is offline."
    exit 
}

# Convert raw string to PowerShell Object
$Data = $Response | ConvertFrom-Json

# --- 5. Generate All 5 Formats ---
Write-Host "Generating files with fixed encoding..." -ForegroundColor Gray

# 1. JSON
Save-Utf8 "$FullBase.json" $Response

# 2. TXT
Save-Utf8 "$FullBase.txt" $Data.text

# 3. SRT
$srt = ""
for ($i=0; $i -lt $Data.segments.Count; $i++) {
    $s = $Data.segments[$i]
    $srt += "$($i+1)`r`n"
    $srt += "$(Format-Time $s.start) --> $(Format-Time $s.end)`r`n"
    $srt += "$($s.text.Trim())`r`n`r`n"
}
Save-Utf8 "$FullBase.srt" $srt

# 4. VTT
$vtt = "WEBVTT`r`n`r`n"
foreach ($s in $Data.segments) {
    $vtt += "$(Format-Time $s.start '.') --> $(Format-Time $s.end '.')`r`n"
    $vtt += "$($s.text.Trim())`r`n`r`n"
}
Save-Utf8 "$FullBase.vtt" $vtt

# 5. TSV
$tsv = "start`tend`ttext`r`n"
foreach ($s in $Data.segments) {
    $tsv += "$($s.start)`t$($s.end)`t$($s.text.Trim())`r`n"
}
Save-Utf8 "$FullBase.tsv" $tsv

Write-Host "Success! All files created in: $OutputDir" -ForegroundColor Green