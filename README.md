# WHISPER - Automated Batch Transcription & AI Summarization Pipeline

[![CI Pipeline](https://github.com/dataquo/WHISPER/actions/workflows/ci.yml/badge.svg)](https://github.com/dataquo/WHISPER/actions/workflows/ci.yml)
[![PowerShell 7.0+](https://img.shields.io/badge/PowerShell-7.0%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Docker](https://img.shields.io/badge/Docker-WhisperX-2496ED.svg)](https://www.docker.com/)

A resilient, high-throughput batch audio transcription and AI summarization orchestrator powered by **PowerShell**, **FFmpeg**, **WhisperX (Docker)**, **Ollama**, and **LM Studio**.

---

## 🌟 Key Features

* **Smart Batch Orchestration**: Automatically scans directories for pending audio files, detects missing output formats, and executes only necessary generation stages without redundant re-transcriptions.
* **Intelligent Filename Convention**: Automatically configures language, acoustic profile, and speaker count directly from file naming patterns (e.g. `recording.SK-M3.mp3`).
* **Profile-Specific Audio Preprocessing**:
  * **`phone`**: Narrow voice bandwidth (200–3500 Hz), speech normalization, broadcast loudness standards.
  * **`meeting`**: Broad frequency range (80–8000 Hz) with dynamic audio normalization for varying speaker distances.
  * **`distant`**: Adaptive compression + noise reduction for ambient room recordings.
* **Speaker Diarization & Multi-Format Output**: Generates `.json`, `.txt`, `.srt`, `.vtt`, and `.tsv` in a single GPU pass.
* **Dual AI Summaries**:
  * **`NOTES.md`**: Detailed structured meeting notes generated via LM Studio / OpenAI-compatible API.
  * **`SUMMARY.md`**: Concise structured summaries generated via Ollama.
* **Hardware Telemetry & Performance Metrics**: Logs Real-Time Factor (RTF), Tokens Per Second (TPS), and full CPU/GPU/RAM hardware telemetry to structured JSON logs.
* **VRAM Memory Optimization**: Automatically manages GPU resources by restarting containers and clearing Ollama memory caches between iterations.

---

## 📁 Repository Structure

```text
WHISPER/
├── .github/
│   └── workflows/
│       ├── ci.yml                 # PSScriptAnalyzer linting + Pester 5 unit tests
│       └── release.yml            # GitHub Release automation on semantic tag push
├── src/
│   ├── _MASTER_WHISPER.ps1        # Batch orchestrator
│   └── whisper-asr-service-docker.ps1 # Core WhisperX + FFmpeg + LLM engine
├── config/
│   ├── config.default.json        # Default API endpoints, profiles, and models
│   └── config.local.json.example  # Template for local environment overrides
├── tests/
│   ├── _MASTER_WHISPER.Tests.ps1  # Unit tests for parameter extraction & checks
│   └── whisper-asr-service-docker.Tests.ps1 # Unit tests for timecodes & converters
├── .gitattributes                # Consistent CRLF line endings for PowerShell
├── .gitignore                    # Media, transcript, and secret exclusions
├── PSScriptAnalyzerSettings.psd1 # Linter rule definitions
└── README.md                     # Project documentation
```

---

## 🏷️ Filename Naming Convention

Name your audio files using the pattern:
```text
[title].[LANG]-[PROFILE][SPEAKERS].[ext]
```

### Components:
* **`LANG`** (2 characters, optional): `CS` (Czech), `SK` (Slovak), `EN` (English), or omitted for Whisper auto-detection.
* **`PROFILE`** (1 character, optional):
  * `P` $\rightarrow$ `phone` profile (2 speakers default)
  * `M` $\rightarrow$ `meeting` profile (variable room acoustics)
  * `D` $\rightarrow$ `distant` profile (noisy/far-field audio)
* **`SPEAKERS`** (integer, optional): Number of distinct diarized speakers.

### Examples:
* `2026-04-14_O2-Rozhovor.CS-P2.m4a` $\rightarrow$ Czech, Phone profile, 2 speakers.
* `TeamSync_Sprint42.SK-M5.mp3` $\rightarrow$ Slovak, Meeting profile, 5 speakers.
* `Conference_Keynote.EN-D1.flac` $\rightarrow$ English, Distant profile, 1 speaker.
* `voice_memo.mp4` $\rightarrow$ Defaults to Phone profile with auto language detection.

---

## 🚀 Quick Start

### 1. Prerequisites
Ensure the following tools are installed and available on your system:
* **PowerShell 7.x+**
* **FFmpeg** (added to system PATH)
* **Docker Desktop** (running `whisper-asr-service` on port 9000)
* **Ollama** (optional, for `SUMMARY.md` on port 11434)
* **LM Studio** (optional, for `NOTES.md` on port 1234)

### 2. Configuration
Copy the configuration template if you need local hardware overrides:
```powershell
Copy-Item config\config.local.json.example config\config.local.json
```

### 3. Run Batch Transcription
Process all audio files in a folder:
```powershell
# Run from repository root
pwsh -File .\src\_MASTER_WHISPER.ps1 -InputFolder "C:\Recordings\Meetings"
```

### 4. Run Single File Transcription
```powershell
pwsh -File .\src\whisper-asr-service-docker.ps1 `
    -FilePath "C:\Recordings\interview.m4a" `
    -Profile phone `
    -Language sk `
    -MinSpeakers 2 `
    -MaxSpeakers 2 `
    -GenerateMode both
```

---

## 🧪 Testing & Quality Assurance

Run Pester unit tests locally:
```powershell
Invoke-Pester -Path ./tests -Output Detailed
```

Run PowerShell static code analysis (PSScriptAnalyzer):
```powershell
Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

---

## 🔄 GitHub Development Workflow

1. **Working on Features**:
   Create a feature branch instead of modifying main directly:
   ```powershell
   git checkout -b feature/my-enhancement
   ```
2. **Committing Changes**:
   Use [GitHub Desktop](https://desktop.github.com/) or the Git CLI:
   ```powershell
   git add .
   git commit -m "feat: description of change"
   git push origin feature/my-enhancement
   ```
3. **Releases**:
   Push a semantic version tag to trigger the automated GitHub Release workflow:
   ```powershell
   git tag -a v5.7.0 -m "Release v5.7.0"
   git push origin v5.7.0
   ```
