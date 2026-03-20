
<#

Based on: https://gemini.google.com/share/6b1dddd87280


Gemini said
This PowerShell script is designed to handle your specific requirements: 
- it allows you to pass a file path and a "profile" (like meeting or phone) which automatically adjusts the AI's sensitivity.
- I have used curl.exe explicitly to avoid conflicts with PowerShell's internal curl alias
-  I've set the phone profile to use the settings we discovered earlier (disabling the VAD filter) to ensure it catches those quiet voices

Run for a normal meeting in PowerShell:
.\transcribe.ps1 -FilePath "C:\path\to\your\recording.mp4" -Profile meeting

Run for that difficult O2 Phone Call in PowerShell: 
.\transcribe.ps1 -FilePath "C:\path\to\O2-Rozhovor.m4a" -Profile phone


#>


param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,

    [Parameter(Mandatory=$false)]
    [ValidateSet("meeting", "phone", "distant", "simple")]
    [string]$Profile = "meeting"
)

# --- 1. Define Profiles ---
# You can adjust these presets to fine-tune your different scenarios.
$ProfileSettings = @{
    "meeting" = @{
        "model"          = "medium"
        "language"       = "sk"
        "diarize"        = "true"
        "vad_filter"     = "true"
        "vad_onset"      = "0.2"
        "vad_offset"     = "0.2"
        "initial_prompt" = "Toto je nahrávka z meetingu v slovenčine, prípadne v češtine. Viacero rečníkov."
        "temperature"    = "0.0"
    }
    "phone" = @{
        "model"          = "medium"
        "language"       = "sk"
        "diarize"        = "true"
        "vad_filter"     = "false"  # DISABLED: Essential for catching quiet phone voices
        "initial_prompt" = "Prepis nahrávky telefonického hovoru. Hlasy môžu byť tiché alebo skreslené."
        "temperature"    = "0.0"
    }
    "distant" = @{
        "model"          = "medium"
        "language"       = "sk"
        "diarize"        = "false"
        "vad_filter"     = "true"
        "vad_onset"      = "0.1"   # VERY SENSITIVE: Catch distant room audio
        "initial_prompt" = "Nahrávka z diaľky v miestnosti. Prosím detekuj aj tichý hlas."
        "temperature"    = "0.2"
    }
}

# --- 2. Build the Parameters ---
$Config = $ProfileSettings[$Profile]

# Check if file exists
if (-not (Test-Path $FilePath)) {
    Write-Error "File not found: $FilePath"
    exit
}

Write-Host "--- Starting Transcription ---" -ForegroundColor Cyan
Write-Host "Profile: $Profile" -ForegroundColor Yellow
Write-Host "File: $FilePath"

# --- 3. Execute CURL ---
# Using curl.exe to ensure we use the system binary, not PowerShell's alias.
# We pass all required documentation parameters here.
& curl.exe -X POST "http://localhost:9000/v1/audio/transcriptions" `
  -H "Content-Type: multipart/form-data" `
  -F "file=@$FilePath" `
  -F "model=$($Config.model)" `
  -F "language=$($Config.language)" `
  -F "task=transcribe" `
  -F "initial_prompt=$($Config.initial_prompt)" `
  -F "diarize=$($Config.diarize)" `
  -F "vad_filter=$($Config.vad_filter)" `
  -F "vad_onset=$($Config.vad_onset)" `
  -F "vad_offset=$($Config.vad_offset)" `
  -F "temperature=$($Config.temperature)" `
  -F "output_format=json" `
  -F "word_timestamps=true"

Write-Host "`n--- Task Finished ---" -ForegroundColor Green