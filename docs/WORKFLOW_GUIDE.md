# WHISPER Operational Runbook & Workflow Guide

This guide provides practical instructions for daily operations, troubleshooting, testing, and developing within the WHISPER repository.

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

### Single File Transcription
To transcribe or re-process a specific audio file:
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

## 2. Docker & Backend Services Management

### Starting the WhisperX Service
Ensure the WhisperX Docker container is running before starting transcription:
```powershell
docker run -d --gpus all -p 9000:9000 --name whisperx-api onerahmet/openai-whisper-asr-webservice:latest-gpu
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

## 3. Local Development & Testing

### Running Pester Unit Tests
To verify all regex parsers, formatters, and logic locally:
```powershell
# In PowerShell terminal
Invoke-Pester -Path ./tests -Output Detailed
```

### Running Static Code Analysis (Linter)
To check PowerShell scripts against project rules:
```powershell
Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

---

## 4. Git & Release Workflow

### Committing & Pushing
> [!IMPORTANT]
> All commits, merges, and pushes are performed manually by the human developer via **GitHub Desktop**.

1. Open **GitHub Desktop**.
2. Review modified files in the **Changes** tab.
3. Enter a clear commit message (e.g. `feat: add whisper beam size parameter`).
4. Click **Commit to main**.
5. Click **Push origin** to sync with GitHub.

### Publishing a New Release
To trigger the automated GitHub Actions release workflow:
1. Create and push a semantic tag:
   ```powershell
   git tag -a v5.7.0 -m "Release v5.7.0 - Support for new LLM model"
   git push origin v5.7.0
   ```
2. GitHub Actions will automatically generate the release on GitHub with release notes.

---

## 5. Troubleshooting Guide

| Problem | Cause | Solution |
| :--- | :--- | :--- |
| `GPU Out of Memory (CUDA OOM)` | Ollama or other LLMs retaining GPU VRAM | Run `ollama stop <model>` or `docker restart whisperx-api`. |
| `Missing MD file warning` | LLM service offline | Check if Ollama (`localhost:11434`) or LM Studio (`10.0.0.162:1234`) is running. |
| `PSScriptAnalyzer warnings` | Formatting or syntax violation | Run `Invoke-ScriptAnalyzer -Path ./src` and fix flagged lines. |
| `Empty transcript generated` | Corrupted audio input | Verify input file plays cleanly in VLC/media player. Check FFmpeg log file. |
