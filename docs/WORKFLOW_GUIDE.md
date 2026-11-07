# WHISPER Operational Runbook & Workflow Guide

This guide provides practical instructions for daily operations, troubleshooting, testing, and developing within the **WHISPER** repository (v06.05).

---

## 1. Daily Operations

### Interactive Help & Parameter Discovery
Whenever you need a quick reminder of supported switches, parameter aliases, or filename tagging syntax:

```powershell
# View full help with complete filename convention syntax and parameter details
Get-Help .\src\_MASTER_WHISPER.ps1 -Full

# View ready-to-run copy-paste command examples
Get-Help .\src\_MASTER_WHISPER.ps1 -Examples

# Fast terminal syntax reminder
.\src\_MASTER_WHISPER.ps1 -?
```

* **IntelliSense Auto-Completion**: In PowerShell 7+, type `.\src\_MASTER_WHISPER.ps1 -` and press <kbd>Tab</kbd> or <kbd>Ctrl</kbd>+<kbd>Space</kbd> to inspect available switches and aliases interactively.

### Batch Processing a Directory
To transcribe all pending recordings in a folder:
```powershell
# Run from repository root
pwsh -File .\src\_MASTER_WHISPER.ps1 -InputFolder "D:\Recordings\2026-August"
```

* The script automatically skips any audio file whose transcripts (`.json`, `.txt`, `.srt`, `.tsv`, `.vtt`, `.NOTES.md`, `.SUMMARY.md`) already exist and are non-empty.
* If only markdown notes are missing, it selectively runs LLM inference without re-running audio transcription.

### Selective LLM Execution Switches
* **Only Ollama Summary (`.SUMMARY.md`)**:
  ```powershell
  pwsh -File .\src\_MASTER_WHISPER.ps1 -InputFolder "D:\Recordings" -OnlyOllama
  ```
  *(Aliases: `-OnlyOllama`, `-OnlyOlama`, `-OllamaOnly`)*

* **Only LM Studio Notes (`.NOTES.md`)**:
  ```powershell
  pwsh -File .\src\_MASTER_WHISPER.ps1 -InputFolder "D:\Recordings" -OnlyLMStudio
  ```
  *(Aliases: `-OnlyLMStudio`, `-OnlyLM`, `-LMStudioOnly`)*

* **Pure WhisperX Transcription (No LLMs)**:
  ```powershell
  pwsh -File .\src\_MASTER_WHISPER.ps1 -InputFolder "D:\Recordings" -DisableLLM
  ```
  *(Aliases: `-DisableLLM`, `-DisableLLMs`, `-SkipLLM`, `-NoLLM`)*

### Single File Transcription
To transcribe or re-process a specific audio file directly with the execution engine:
```powershell
pwsh -File .\src\whisper-asr-service-docker.ps1 `
    -FilePath "D:\Recordings\corridor_camera.SK-E2.mp4" `
    -Profile echoed `
    -Language sk `
    -MinSpeakers 2 `
    -MaxSpeakers 2 `
    -GenerateMode both `
    -DebugMode
```

---

## 2. IP Security Camera Audio Optimization (Hikvision / HiLook)

When transcribing CCTV audio captured in reverberant spaces (concrete hallways, stairwells):

### Recommended Camera Settings (Web UI / iVMS-4200):
1. Navigate to: **Configuration $\to$ Video/Audio $\to$ Audio**.
2. **Audio Encoding**: Change from `G.711ulaw` (8 kHz) to **`AAC`** (or `MP2L2`).
3. **Sampling Rate**: Set to **`16 kHz`** (or 32/44.1 kHz if available).
4. **Audio Stream Bitrate**: Set to **`64 kbps`** or **`128 kbps`**.
5. **Environmental Noise Filtering**: Toggle to **`ON`** (activates hardware DSP filter on camera DSP chip).
6. **Input Volume**: Reduce from 100% to **`60 – 70%`** (prevents microphone diaphragm clipping in reverberant corridors).

### Impact on Whisper ASR Accuracy:
* **8 kHz G.711u**: Max frequency ~3.7 kHz. Slovak sibilants (*s, š, c, č, z, ž, f, t*) are cut off, forcing the model to guess words.
* **16 kHz AAC**: Preserves frequencies up to 8.0 kHz, providing full phonetic resolution for 95%+ transcription accuracy.

---

## 3. Local Machine Configuration (`config.local.json`)

To customize settings for your individual developer environment without modifying tracked repository files:

1. Copy `config/config.local.json.example` to `config/config.local.json`:
   ```powershell
   Copy-Item "config/config.local.json.example" "config/config.local.json"
   ```
2. Adjust properties specific to your machine (e.g. your local container name or remote LM Studio host):
   ```json
   {
     "whisper_service": {
       "docker_container_name": "whisperx-api"
     },
     "lm_studio_service": {
       "api_url": "http://192.168.1.50:1234/v1/chat/completions"
     }
   }
   ```
3. `config/config.local.json` is ignored by Git (`.gitignore`), ensuring your machine configuration is never committed.

---

## 4. Docker & Backend Services Management

### Starting the WhisperX Service
The execution engine automatically starts the container if stopped (`auto_restart_container: true`). To start it manually:
```powershell
docker start whisper-asr-service
# Or if your container is named whisperx-api:
docker start whisperx-api
```

### Checking Service Health
```powershell
# Test WhisperX API
curl.exe -s http://localhost:9000/docs

# Test Ollama API
curl.exe -s http://localhost:11434/api/tags

# Test LM Studio Endpoint
curl.exe -s http://10.0.0.162:1234/v1/models
```

### Auditing Pipeline & Container Telemetry in `.log` Files
Every transcription run produces a JSON execution log (`{basename}.WHISPER.YYYYMMDD-HHmmss.log`). To inspect the runtime environment, script version, and Docker container details from PowerShell:

```powershell
# Parse the latest transcription log as JSON
$log = Get-Content .\Recordings\meeting.WHISPER.*.log -Tail 100 | Out-String | ConvertFrom-Json

# Inspect script version and execution identity
$log | Select-Object script_name, script_version, execution_time

# Inspect Docker container environment
$log.container_information | Format-List

# Inspect ASR decoding parameters & model
$log.api_parameters
$log.configuration_parameters
```

---

## 5. Local Development & Testing

### Running Pester Unit Tests
To verify all regex parsers, formatters, configuration loaders, and lifecycle logic:
```powershell
Invoke-Pester -Path ./tests -Output Detailed
```

### Running Static Code Analysis (Linter)
To check PowerShell scripts against project rules:
```powershell
Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

---

## 6. Git & Release Workflow

### Committing & Pushing
> [!IMPORTANT]
> All commits, merges, and pushes are performed manually by the human developer via **GitHub Desktop**. The AI agent is strictly forbidden from running `git commit`, `git push`, or `git tag`.

1. Open **GitHub Desktop**.
2. Review modified files in the **Changes** tab.
3. Enter a clear commit message.
4. Click **Commit to main** and then **Push origin**.

---

## 7. Troubleshooting Guide

| Problem | Cause | Solution |
| :--- | :--- | :--- |
| `Cannot restart container: '...' not found` | Local container name differs from `config.default.json` | Set `"docker_container_name"` in `config/config.local.json`. |
| `Container metadata fields (image, cudnn) are null in log` | Docker daemon unreachable or non-standard container name | Ensure Docker is running. The engine automatically attempts fallback inspection on `whisperx-api` and `whisper-asr-service`. |
| `Model hallucinates parliamentary phrases` | Slovak fine-tuned model (`kinit-sk`) running on muffled echo audio | Switch filename tag from `.SK-H2` to `.SK-E2` (`echoed` profile uses neutral OpenAI `large-v3`). |
| `Repeating word loops ("na päťkrát...")` | Low acoustic clarity causing beam search loop | Handled automatically in profile `echoed` (`beam_size=1`, `repetition_penalty=1.2`). |
| `GPU Out of Memory (CUDA OOM)` | Ollama or other LLMs retaining GPU VRAM | Whisper engine automatically restarts the container. Or run `ollama stop <model>`. |
| `Audio preprocessing yielded empty/invalid stream` | Video file has no audio stream or corrupt track | Input file contains no sound. Check FFmpeg log (`.log`) in target directory. |
| `Opening greetings have no speaker label ([NONE])` | PyAnnote left-edge receptive field boundary deficit on immediate speech | Enable `"lead_in_silence_seconds": 1.5` in profile configuration to prepend lead-in padding (see ADR 0010). |
| `Single speaker label covers both question and answer` | Trailing word stretched across pause into next speaker's turn by Wav2Vec2 | Inherent limitation of Wav2Vec2 forced alignment without VAD token. See detailed analysis in ADR 0010. |
| `Accented characters stripped from text` | Windows-1252 / UTF-8 encoding mismatch in regex | Enforce UTF-8 without BOM (`$Utf8NoBom`) and use unicode escapes (`\u2013\u2014`) in regex cleaners. |
| `MetadataError: parameter alias conflict` | Case-insensitive alias collision in PowerShell | Resolved in v06.01; ensure all parameters use clean, distinct aliases. |
| `PSScriptAnalyzer warnings` | Formatting or syntax violation | Run `Invoke-ScriptAnalyzer -Path ./src` and fix flagged lines. |
| `Processed audio file not found` / missing FFmpeg log warnings on files with `[...]` | PowerShell `-Path` treating square brackets as wildcard globbing pattern | Enforce `-LiteralPath` across all PowerShell provider cmdlets (`Test-Path`, `Get-Content`, `Move-Item`, `Get-Item`). Resolved in v06.04 (see ADR 0012). |