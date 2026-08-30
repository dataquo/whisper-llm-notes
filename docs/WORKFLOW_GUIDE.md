# WHISPER Operational Runbook & Workflow Guide

This guide provides practical instructions for daily operations, troubleshooting, testing, and developing within the **WHISPER** repository (v06.00).

---

## 1. Daily Operations

### Batch Processing a Directory
To transcribe all pending recordings in a folder:
```powershell
# Run from repository root
pwsh -File .\src\_MASTER_WHISPER.ps1 -InputFolder "D:\Recordings\2026-August"
```

* The script automatically skips any audio file whose transcripts (`.json`, `.txt`, `.srt`, `.tsv`, `.vtt`, `.NOTES.md`, `.SUMMARY.md`) already exist and are non-empty.
* If only markdown notes are missing, it selectively runs LLM inference without re-running audio transcription.

### Batch Transcription without LLMs (`-DisableLLMs`)
To run pure WhisperX transcription (generating `.json`, `.txt`, `.srt`, `.tsv`, `.vtt`) and skip Ollama & LM Studio summarization:
```powershell
pwsh -File .\src\_MASTER_WHISPER.ps1 -InputFolder "D:\Recordings\2026-August" -DisableLLMs
```
*(Aliases: `-DisableLLMs`, `-DisableLLM`, `-SkipLLM`, `-NoLLM`)*

### Single File Transcription
To transcribe or re-process a specific audio file directly with the execution engine:
```powershell
pwsh -File .\src\whisper-asr-service-docker.ps1 `
    -FilePath "D:\Recordings\meeting.m4a" `
    -Profile meeting `
    -Language sk `
    -MinSpeakers 3 `
    -MaxSpeakers 5 `
    -GenerateMode both `
    -DebugMode
```

---

## 2. Local Machine Configuration (`config.local.json`)

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

## 3. Docker & Backend Services Management

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

---

## 4. Local Development & Testing

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

## 5. Git & Release Workflow

### Committing & Pushing
> [!IMPORTANT]
> All commits, merges, and pushes are performed manually by the human developer via **GitHub Desktop**. The AI agent is strictly forbidden from running `git commit`, `git push`, or `git tag`.

1. Open **GitHub Desktop**.
2. Review modified files in the **Changes** tab.
3. Enter a clear commit message.
4. Click **Commit to main** and then **Push origin**.

---

## 6. Troubleshooting Guide

| Problem | Cause | Solution |
| :--- | :--- | :--- |
| `Cannot restart container: '...' not found` | Local container name differs from `config.default.json` | Set `"docker_container_name"` in `config/config.local.json`. |
| `GPU Out of Memory (CUDA OOM)` | Ollama or other LLMs retaining GPU VRAM | Whisper engine automatically restarts the container. Or run `ollama stop <model>`. |
| `Audio preprocessing yielded empty/invalid stream` | Video file has no audio stream or corrupt track | Input file contains no sound. Check FFmpeg log (`.log`) in target directory. |
| `PSScriptAnalyzer warnings` | Formatting or syntax violation | Run `Invoke-ScriptAnalyzer -Path ./src` and fix flagged lines. |
| `FastAPI HTTP 422 Unprocessable Entity` | Empty/malformed query string | Handled automatically in v06.00; verify parameters in `config.default.json`. |