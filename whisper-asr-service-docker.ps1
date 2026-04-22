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
| phone | `PHONE-NORM_HP-LW-SP-LN` | highpass(200Hz), lowpass(3500Hz), speechnorm, loudnorm | Narrow speech bandwidth for phone calls |
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

The v04.06 
- functionality has already been fully implemented in the `whisper-asr-service-docker.v04.06.ps1` file. 
- Performance Metrics (v04.06) implemented to calculate and log:
- __Total Processing Time__: Calculated from transcription start to end time
- __Real-Time Factor (RTF)__: Ratio of processing time to audio duration (lower is better)
- __Approx. Token Count__: Based on 1 token ≈ 4 characters rule
- __Tokens Per Second (TPS)__: Calculated throughput metric
- These metrics are both displayed in the console output and logged to the JSON log file via the `Write-CompletionSummary` function.
- issues related to special characters in file names(commas, dots, spaces) that aren't being properly escaped when passed to curl.exe. fiex liek ```powershell -F "audio_file=@$TempProcessedFile"```
- The original error occurred because `curl.exe` was receiving the entire transcript (potentially thousands of characters) as a command-line argument, exceeding Windows' MAX_COMMAND_LINE limit. By using PowerShell's native `Invoke-RestMethod`, the JSON payload is sent in the HTTP request body rather than the command line, avoiding this limitation entirely.




#>



param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,

    [Parameter(Mandatory=$false)]
    [ValidateSet("meeting", "phone", "distant")]
    [string]$Profile = "phone", # Defaulting to phone based on your last run

    [Parameter(Mandatory=$false)]
    [ValidateSet("cs", "sk", "en", "auto")]
    [string]$Language, # Optional language code (e.g., "cs", "sk") - if not provided, API auto-detects

    [switch]$DebugMode # Enable verbose/debug output when specified
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
    
    # Try NVIDIA WMI for additional GPU info (for external NVIDIA GPUs)
    try {
        $nvidiaGpus = Get-WmiObject -Namespace "root\NVIDIA" -Query "SELECT Name, DriverVersion, DeviceID FROM NVIDIA_GPUInformation" 2>$null
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

# --- 2b. Script Version Detection ---

# Extract script version dynamically from the filename (e.g., whisper-asr-service-docker.v04.06.ps1 -> v04.06)
$ScriptVersion = if ($MyInvocation.MyCommand.Path) {
    $ScriptPath = $MyInvocation.MyCommand.Path
    $FileName = [System.IO.Path]::GetFileName($ScriptPath)
    # Extract version from pattern *.vXX.YY.ps1 or whisper-asr-service-docker.vXX.YY.ps1
    if ($FileName -match "v(\d+\.\d+)(\.\d+)?\.ps1$") {
        "whisper-asr-service-docker.v$($Matches[1])"
    } else {
        $FileName
    }
} else {
    "whisper-asr-service-docker.v04.06.ps1"  # Fallback for safety
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
        [string]$FullUrl,
        [string]$QueryString,
        [string]$ProcessedFile,
        [string]$TempProcessedFile
    )
    
    # v04.04 - New log filename pattern: ProcessedFile.WHISPER.YYYYMMDD-HHmmss.log (matching processed audio file naming)
    $TimestampSuffix = Get-Date -Format "yyyyMMdd-HHmmss"
    # Extract just the base filename from TempProcessedFile, then append .WHISPER.timestamp.log suffix
    $BaseFileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $LogFileName = "$BaseFileName.WHISPER.$TimestampSuffix.log"
    # Combine with output directory to get full path
    $LogPath = [System.IO.Path]::Combine($OutputDir, $LogFileName)
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $DayOfWeek = (Get-Date).ToString("dddd")
    
    # v04.04/04.05 - Machine-readable JSON format for log file
    $SystemInfo = Get-SystemInfo
    
    $LogData = @{
        script_version = $ScriptVersion
        execution_time = $Timestamp
        day_of_week = $DayOfWeek
        
        system_information = $SystemInfo
        
        configuration_parameters = @{
            profile = $Profile
            diarize = $Config.diarize
            vad_filter = $Config.vad_filter
            vad_onset = $Config.vad_onset
            vad_offset = $Config.vad_offset
            min_speakers = $Config.min_speakers
            max_speakers = $Config.max_speakers
            initial_prompt = $Config.initial_prompt.Replace("`r`n", " ")
            temperature = $Config.temperature
        }
        
        api_parameters = @{
            language = $Language
            model = "large-v3"
        }
        
        query_string = $QueryString
        full_api_url = $FullUrl
        
        processing_information = @{
            input_file = $FilePath
            processed_file = $ProcessedFile
        }
    }
    
    # Write initial log file as JSON (will append to later)
    $LogData | ConvertTo-Json -Depth 10 | Set-Content -Path $LogPath
    
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
    
    # Read existing JSON and add timing data
    $ExistingData = Get-Content $LogPath | ConvertFrom-Json
    
    # Create new object with all properties plus the new timing property
    # Note: system_information is already in $ExistingData from New-TranscriptionLog
    $UpdatedData = [PSCustomObject]@{
        script_version = $ExistingData.script_version
        execution_time = $ExistingData.execution_time
        day_of_week = $ExistingData.day_of_week
        system_information = $ExistingData.system_information
        configuration_parameters = $ExistingData.configuration_parameters
        api_parameters = $ExistingData.api_parameters
        query_string = $ExistingData.query_string
        full_api_url = $ExistingData.full_api_url
        processing_information = $ExistingData.processing_information
        timing = @{
            start_time = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
            end_time = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
            total_duration_seconds = $TotalSeconds
        }
        performance_metrics = @{
            audio_duration_seconds = [Math]::Round($AudioDuration, 2)
            processing_time_seconds = [Math]::Round($ProcessingTime, 2)
            real_time_factor_rtf = [Math]::Round($RTF, 3)
            approx_token_count = $TokenCount
            tokens_per_second_tps = [Math]::Round($TPS, 2)
        }
    }
    
    # Write updated JSON back to file
    $UpdatedData | ConvertTo-Json -Depth 10 | Set-Content -Path $LogPath
    
    Write-Host "Log file saved: $LogPath" -ForegroundColor Cyan
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
        "max_speakers"   = "5"        
        "temperature"    = "0.0"
    }
    "phone" = @{
        "diarize"        = "true"
        "vad_filter"     = "true"   # WhisperX's diarization engine (Pyannote) heavily relies on the VAD (Voice Activity Detection) map to know where segments begin and end. If you turn the VAD filter OFF, you are sending a raw "blob" of audio to the diarization model.
        "vad_onset"      = "0.5"    # Less sensitive. The diarization engine (Pyannote) needs a solid "chunk" of audio (usually 0.5s or more) to identify a voice. If the segments are too short, it fails to identify who is speaking.
        "vad_offset"     = "0.5"    # Less sensitive        
        "initial_prompt" = "Přepis nahrávky telefonického hovoru. Hlasy mohou být zkreslené."
        "min_speakers"   = "2"        
        "max_speakers"   = "2"      # Hard limit to 2 people   
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




Write-Host "`n ========================  File processing started  ========================" -ForegroundColor Green

# --- Record Start Time for Logging ---
$StartTime = Get-Date
Write-Host "Transcription start time: $($StartTime.ToString("yyyy-MM-dd HH:mm:ss"))" -ForegroundColor Cyan

$Config = $ProfileSettings[$Profile]
$BaseName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
$OutputDir = [System.IO.Path]::GetDirectoryName($FilePath)
$FullBase = Join-Path $OutputDir $BaseName

# v03.04 - FFmpeg preprocessing integration: define processed file naming based on profile (switchable WAV/MP3)
switch ($Profile) {
    "phone"     { $ProcessedSuffix = "PHONE-NORM_HP-LW-SP-LN" }
    "meeting"   { $ProcessedSuffix = "MEETING-NORM_HP-LW-DN" }
    "distant"   { $ProcessedSuffix = "DISTANT-NORM_HP-LP-AC-SN" }
    default     { $ProcessedSuffix = "${Profile}-processed" }
}




# v03.04 - FFmpeg WAV encoding parameters (PCM 16-bit LE) - NCOMMENT TO USE WAV
# $FfMpegWavParams = "-acodec pcm_s16le"

# v03.04 - FFmpeg MP3 encoding parameters (libmp3lame, 64kbps) - UNCOMMENT TO USE MP3
$FfMpegMp3Params = "-acodec libmp3lame -b:a 64k"


# v03.04 - Determine output format based on active codec and set file path
if ($FfMpegWavParams) {
    $OutputFormat = "wav"
    $FfMpegOutputParams = $FfMpegWavParams
} else {
    $OutputFormat = "mp3"
    $FfMpegOutputParams = $FfMpegMp3Params
}
$TempProcessedFile = "$OutputDir\$BaseName.$ProcessedSuffix.$OutputFormat"






# v03.06 - Check if processed file already exists to skip redundant FFmpeg conversion
Write-Host "Checking for existing processed file: $TempProcessedFile" -ForegroundColor Gray

if (Test-Path $TempProcessedFile) {
    Write-Host "Processed file already exists: $TempProcessedFile" -ForegroundColor Cyan
    Write-Host "Skipping FFmpeg preprocessing..." -ForegroundColor Yellow
} else {
    # v03.03 - FFmpeg preprocessing integration: profile-specific pipeline selection
    # Preprocess audio file using FFmpeg before upload (profile-specific pipelines)
    Write-Host "Preprocessing audio file with FFmpeg ($Profile profile)..." -ForegroundColor Yellow

    switch ($Profile) {
    "phone" {
        # v03.03 - Phone: Speech-focused, narrow bandwidth (200-3500Hz), speech normalization -> WAV PCM uncompressed or MP3 (libmp3lame, 64kbps)
        $FfMpegCmd = "ffmpeg.exe -i `"$FilePath`" -af `"highpass=f=200, lowpass=f=3500, speechnorm=e=10:r=0.0005:l=1, loudnorm=I=-16:TP=-1.5:LRA=11`" $FfMpegOutputParams -ar 16000 `"$TempProcessedFile`" -y"
    }
    "meeting" {
        # v03.03 - Meeting: Full speech range (80-8000Hz), dynamic normalization for variable room acoustics -> WAV PCM uncompressed or MP3 (libmp3lame, 64kbps)
        $FfMpegCmd = "ffmpeg.exe -i `"$FilePath`" -af `"highpass=f=80, lowpass=f=8000, dynaudnorm=p=0.9:m=50:s=5:g=15, loudnorm=I=-16:TP=-1.5:LRA=11`" $FfMpegOutputParams -ar 16000 `"$TempProcessedFile`" -y"
    }
    "distant" {
        # v03.03 - Distant: Narrower bandwidth (200-4000Hz), compressor + speech normalization for noisy environments -> WAV PCM uncompressed or MP3 (libmp3lame, 64kbps)
        $FfMpegCmd = "ffmpeg.exe -i `"$FilePath`" -af `"highpass=f=200, lowpass=f=4000, acompressor=threshold=-20dB:ratio=10:attack=5:release=50:makeup=8, speechnorm=e=30:r=0.0001:l=1, loudnorm=I=-16:TP=-1.5:LRA=11`" $FfMpegOutputParams -ar 16000 `"$TempProcessedFile`" -y"
    }
    default {
        # v03.03 - Default: Same as phone profile -> WAV PCM uncompressed or MP3 (libmp3lame, 64kbps)
        $FfMpegCmd = "ffmpeg.exe -i `"$FilePath`" -af `"highpass=f=200, lowpass=f=3500, speechnorm=e=10:r=0.0005:l=1, loudnorm=I=-16:TP=-1.5:LRA=11`" $FfMpegOutputParams -ar 16000 `"$TempProcessedFile`" -y"
        }
    }

    # v03.05 - Set FFREPORT environment variable for FFmpeg logging with timestamped filename
    $LogFileName = "$OutputDir\$BaseName.$ProcessedSuffix.$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $env:FFREPORT = "file='$LogFileName':level=48"

    $FfMpegResult = Invoke-Expression $FfMpegCmd

    if ($LASTEXITCODE -ne 0) { 
        Write-Error "FFmpeg preprocessing failed. Check ffmpeg is installed and accessible.`nExit Code: $LASTEXITCODE"
        exit 
    }

    Write-Host "Success! Audio preprocessed successfully: $TempProcessedFile" -ForegroundColor Green
}


<##>
# TEMPOARY COMMENT OUT TO TEST API CALL WITHOUT FFmpeg PREPROCESSING (SENDING ORIGINAL FILE INSTEAD OF PROCESSED FILE)

# Check if JSON file already exists - skip to summarization if so
    if (-not (Test-Path "$FullBase.json")) {


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
    $BaseUrl = "http://localhost:9000/asr"

    # Helper function to URL-encode strings
    function ConvertTo-UrlEncoded($String) {
        [System.Web.HttpUtility]::UrlEncode($String)

    }

    # Build URL with properly encoded parameters
    $QueryParams = @{
        "task"            = "transcribe"
        "language"        = $Language
        "model"           = "large-v3"                          # You can change this to "large-v3" or "medium" or "small" if you want faster processing with less accuracy
        "diarize"         = $Config.diarize
        "min_speakers"    = $Config.min_speakers
        "max_speakers"    = $Config.max_speakers
        "initial_prompt"  = $Config.initial_prompt
        "vad_filter"      = $Config.vad_filter
        "vad_onset"       = $Config.vad_onset
        "vad_offset"      = $Config.vad_offset
        "temperature"     = $Config.temperature
        # "beam_size"       = "2"                                  # Optional: Adjust beam size as large model fails. (default is 5, lower is faster but less accurate, higher is slower but more accurate)
    }

    $QueryString = (($QueryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$(ConvertTo-UrlEncoded $_.Value)" }) -join "&")
    $FullUrl = "$BaseUrl`?$QueryString"

    # Create the transcription log file with all parameters
    $LogPath = New-TranscriptionLog `
        -BaseName $BaseName `
        -OutputDir $OutputDir `
        -Profile $Profile `
        -Config $Config `
        -Language $Language `
        -FullUrl $FullUrl `
        -QueryString $QueryString `
        -ProcessedFile $TempProcessedFile `
        -TempProcessedFile $TempProcessedFile


    # Write BaseURL
    # Write-Host "Base API URL: $BaseUrl" -ForegroundColor Green

    # Debug mode logging (only shown when -DebugMode is specified)
    if ($DebugMode) {
        Write-Host "Full API URL: $FullUrl" -ForegroundColor Green
    }

    # Write Temp Processed File Path
    Write-Host "Audio file for transcription: $TempProcessedFile" -ForegroundColor Green 




    
    if (-not (Test-Path $FilePath)) { Write-Error "File not found: $FilePath"; exit }

    # --- 4. API Call (Updated to Native Endpoint) ---
    Write-Host "Sending request to Native WhisperX Endpoint..." -ForegroundColor Gray


    Write-Host "Starting Transcription..." -ForegroundColor Cyan
    Write-Host "Profile: $Profile | Language: $Language" -ForegroundColor Yellow

    # Show initial progress state
    Write-Progress -Activity "Processing Audio File" -Status "Starting transcription..." -PercentComplete 20

    # Execute the call (Sending ONLY the audio file as form data)
    # Use proper quoting for curl -F parameter to handle special characters like commas and spaces
    # The pattern "-F audio_file=@""path/to/file""" works correctly with curl.exe
    $Response = & curl.exe -s -X POST $FullUrl `
      -H "accept: application/json" `
      -H "Content-Type: multipart/form-data" `
      -F ("audio_file=@" + "`"$TempProcessedFile`"")

    
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
        if ($ApiResult.detail -match "(?i)(cuda|gpu|memory|device unavailable)") {
            Write-Host "GPU error detected: $($ApiResult.detail)" -ForegroundColor Red
            Write-Host "Skipping file generation and flushing GPU VRAM..." -ForegroundColor Yellow
            
            # Restart container to recover from GPU out-of-memory state
            Write-Host "Flushing GPU VRAM by restarting Docker container..." -ForegroundColor DarkYellow
            docker restart whisperx-api | Out-Null
            Start-Sleep -Seconds 10
            Write-Host "Ready for next file." -ForegroundColor Green
            exit
        } else {
            # Non-GPU related error (e.g., validation errors)
            Write-Error "Transcription failed.`nAPI Error: $($ApiResult.detail)"
            exit 
        }
    }
    
    # Show processing state
    Write-Progress -Activity "Processing Audio File" -Status "Processing transcription..." -PercentComplete 50
    
    if (-not $ApiResult.segments) { 
        Write-Error "Transcription returned no segments.`nResponse: $($Response | ConvertTo-Json)"
        exit 
    }
    
    # v04.04 - Record transcription end time immediately after successful API response, before container restart
    $TranscriptionEndTime = Get-Date

    # Use parsed result for file generation
    $Data = $ApiResult
    
    # Show generation state
    Write-Progress -Activity "Processing Audio File" -Status "Generating output files..." -PercentComplete 60


    # 1. JSON (Already contains speaker data)
    Write-Progress -Activity "Processing generated JSON File" -Status "Generating output files..." -PercentComplete 70

    Save-Utf8 "$FullBase.json" $Response

    Start-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formats
    
    # --- 6. Automate the Container Restart--

    Write-Host "Flushing GPU VRAM by restarting Docker container..." -ForegroundColor DarkYellow
    docker restart whisperx-api | Out-Null
    Start-Sleep -Seconds 5 # Give the API a few seconds to boot back up for the next run


} else {
    # JSON file exists, skip API call but read it into $Data for other format generation
    Write-Host "JSON file already exists ($($FullBase).json), skipping WhisperX API call..." -ForegroundColor Yellow
    Write-Host "Reading existing JSON to populate data for other format generation..." -ForegroundColor Cyan
    
    # Re-read $Data from existing JSON since segments weren't populated in this run
    try {
        $JsonContent = Get-Content "$FullBase.json" -Raw -ErrorAction Stop
        $ApiResult = $JsonContent | ConvertFrom-Json
        if (-not $ApiResult.segments) { 
            Write-Error "Existing JSON file has no segments. Please re-run transcription.`nResponse: $($JsonContent)"
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
foreach ($s in $Data.segments) {
    $speakerPrefix = if ($s.speaker) { "[$($s.speaker)]: " } else { "" }
    $txt += "$speakerPrefix$($s.text.Trim())`r`n"
}
Save-Utf8 "$FullBase.txt" $txt
<##>
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
Write-Progress -Activity "Generating TSV File with different speakers" -Status "Generating output files..." -PercentComplete 98

$tsv = "start`tend`tspeaker`ttext`r`n"
foreach ($s in $Data.segments) {
    $tsv += "$($s.start)`t$($s.end)`t$($s.speaker)`t$($s.text.Trim())`r`n"
}
Save-Utf8 "$FullBase.tsv" $tsv

Start-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formatsStart-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formats

# Processed audio files are kept for review/analysis. To delete automatically, remove this block.
Write-Progress -Activity "Processing Audio File" -Status "Completed!" -PercentComplete 100 -Completed

Start-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formatsStart-Sleep -Seconds 1 # Small pause to ensure file is written before we read it again for other formats

Write-Host "Success! All files TXT, SRT, VTT, and TSV created in: $OutputDir" -ForegroundColor Green




# --- 7. Calculate Performance Metrics (v04.06) ---
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
$txtContent = Get-Content "$FullBase.txt" -Raw
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
if ($LogPath -and (Test-Path $LogPath)) {
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

# --- 8. Ollama Summarization Step ---
Write-Host "Starting to process generate summary with Ollama..." -ForegroundColor Cyan

Write-Progress -Activity "Generating Summary with Ollama" -Status "Creating MD summary..." -PercentComplete 66

$OllamaModel = "gemma3:4b"
$TranscriptPath = "$FullBase.txt"

# Read the transcript file content to include in the prompt
if (Test-Path $TranscriptPath) {
    $TranscriptContent = Get-Content -Raw $TranscriptPath
} else {
    Write-Warning "Transcript file not found: $TranscriptPath. Skipping summary generation."
    $TranscriptContent = ""
}

$SummaryPrompt = @"
Please create a detailed structured summary of this audio transcript in the original language of the transcript file. 

Rules:
1. Include speaker names if possible (or speaker labels if not possible to deduce names)
2. One of the speaker is Martin, another speaker can be derived from topic or transcript (if name mentioned)
3. include timestamps if deemed relevant to the content of the conversation (e.g., important decisions, action items, topic changes) 

TRANSCRIPT TOPIC: $BaseName 
- the initial number is hardcoded date in the format YYYY-MM-DD or YYMMDD, please always format the date as "DD MonthName YYYY" (e.g., 14 April 2024) in the summary file
- based on the date,include the day of the week as well (e.g., Sunday, 14 April 2024)
- the initial number is followed by a descriptive title that can be used to understand the topic of the conversation and potentially identify speakers 

TRANSCRIPT CONTENT:
$TranscriptContent

Format: 
- The summary file should be in markdown .MD format with clear sections and bullet points where appropriate. 

Language: 
- The whole summary MD  file should be in the same language as the transcript file
- if the transcript is in Czech, write the summary in Czech. If the transcript is in Slovak, write the summary in Slovak. If the transcript is in English, write the summary in English.
- it will be either Czech or Slovak or English, always pick one and only one for the whole MD file 

"@

try {
    # Build the request body as a PowerShell object, then convert to JSON
    $RequestBody = @{
        model   = $OllamaModel
        prompt  = $SummaryPrompt
        stream  = $false
    } | ConvertTo-Json
    
    # Use Invoke-RestMethod instead of curl.exe to avoid command-line length limitations
    $SummaryResponse = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" `
                                         -Method POST `
                                         -ContentType "application/json" `
                                         -Body $RequestBody
    
    if ($SummaryResponse.response) {
        Save-Utf8 "$FullBase.md" $SummaryResponse.response
        Write-Host "Success! Summary MD created: $($FullBase).md" -ForegroundColor Green
    } else {
        Write-Host "Ollama returned empty response. Check if Ollama is running with model '$OllamaModel'." -ForegroundColor Red
    }
} catch {
    Write-Host "Ollama summarization failed: $_. Ensure Ollama is running and the model '$OllamaModel' is available." -ForegroundColor Red
}


Write-Host "========================  File processing finished  ========================`n" -ForegroundColor Green
