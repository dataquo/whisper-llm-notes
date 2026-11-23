# WHISPER - Automated Batch Transcription & AI Summarization Pipeline

[![CI Pipeline](https://github.com/dataquo/WHISPER/actions/workflows/ci.yml/badge.svg)](https://github.com/dataquo/WHISPER/actions/workflows/ci.yml)
[![PowerShell 7.0+](https://img.shields.io/badge/PowerShell-7.0%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Docker](https://img.shields.io/badge/Docker-WhisperX-2496ED.svg)](https://www.docker.com/)
[![Version](https://img.shields.io/badge/Version-v07.00-brightgreen.svg)](CHANGELOG.md)

A resilient, high-throughput batch audio transcription and AI summarization pipeline powered by **PowerShell 7+**, **FFmpeg**, **WhisperX (Docker & Apple MLX)**, **Ollama**, and **LM Studio**.

---

## 🌟 Key Features

* **Cross-Platform Execution (Windows 11 & macOS Apple Silicon M2 Max)**: Runs with 100% native GPU acceleration on both Windows 11 (NVIDIA CUDA via Docker) and macOS (Apple Silicon M2 Max via native `mlx-whisper` Metal GPU and PyTorch MPS). Single PowerShell codebase for both operating systems.
* **Smart Batch Orchestration**: Automatically scans folders for media files, inspects existing output formats, and executes only missing stages without redundant re-transcriptions.
* **External Video Pre-Processing Orchestration**: Integrates companion video conversion (`..\DJI\convert_DJI_videos_with_MetaData.ps1`) to transcode high-resolution captures via SVT-AV1 preset 2 (`CRF 44`), Opus audio, and hardware CUDA decoding prior to ASR. Includes smart duplicate suppression for converted `.webm` files and bypass control via `-SkipDJI`.
* **Intelligent Filename Tagging**: Automatically detects language, DSP profile, and speaker counts directly from file naming patterns (e.g. `recording.SK-E2.mp4`), resilient against video transcode suffixes (`.CRF-44_LIBSVT-AV1...`).
* **High-Visibility Terminal Alerts**: Emits prominent red warnings whenever media files lack profile tagging, notifying users that defaults are being applied and encouraging standard convention.
* **Resilient Silence & Zero-Speech Handling**: Patched WhisperX VAD pipeline and PowerShell output generators prevent crashes on quiet or silent audio, gracefully outputting blank transcripts without stalling folder batches.
* **Profile-Based FFmpeg Audio DSP**:
  * **`phone` (`P`)**: Telephony speech bandpass (200–3500 Hz), speech normalization, 1.5s lead-in silence priming, broadcast loudness standards (-16 LUFS).
  * **`meeting` (`M`)**: Broad frequency range (80–8000 Hz) with dynamic audio normalization for variable acoustics.
  * **`distant` (`D`)**: Adaptive compression + noise suppression for noisy or far-field microphones.
  * **`hallway` (`H`)**: Corridor / CCTV microphone filter chain (HP 220Hz, LP 3700Hz, `afftdn`, 380Hz notch EQ) paired with Slovak fine-tuned model (`kinit-sk`).
  * **`echoed` (`E`)**: Specialized reverberation profile with greedy ASR decoding (`beam_size=1`, `repetition_penalty=1.2`) to suppress echoing hallucination loops across all languages.
  * **Multi-Channel Compatibility**: Automatically downmixes multi-channel audio (e.g. 5.1, 7.1 HE-AAC) to mono 16 kHz.
* **Lead-in Silence & Sub-Second Timestamp Synchronization**: Prepends configurable lead-in silence margins to prime PyAnnote's temporal receptive field, with automatic sub-second offset subtraction across all 5 generated formats (.json, .txt, .srt, .vtt, .tsv).
* **Speaker Diarization & Multi-Format Export**: Generates `.json`, `.txt`, `.srt`, `.vtt`, and `.tsv` in a single GPU pass with stutter deduplication.
* **Context-Aware Dual AI Summarization**:
  * **`NOTES.md`**: Detailed structured meeting notes generated via LM Studio / OpenAI-compatible API with acoustic error reconstruction.
  * **`SUMMARY.md`**: Concise structured executive summaries generated via Ollama.
  * **Selective Execution Modes**: Trigger specific LLMs via `-OnlyOllama`, `-OnlyLMStudio`, or skip them entirely with `-DisableLLM`.
* **Integrated CLI Discoverability & Help**: Rich PowerShell Comment-Based Help with `-Full`, `-Examples`, `-?`, and interactive parameter auto-completion.
* **Automatic Language Guard**: Safeguards fine-tuned language-specific models (e.g. `kinit-sk`) to be used strictly for Slovak, falling back to multilingual `large-v3` for Czech and English.
* **Deterministic Docker Lifecycle & VRAM Flushing**:
  * Automatically starts stopped containers and polls `/docs` or `/health` until ready.
  * Flushes GPU VRAM after each file and recovers from CUDA out-of-memory errors by restarting the configured container.
* **Deep Configuration Layering**: Base defaults in `config.default.json` with untracked machine-specific overrides in `config.local.json`.
* **Universal Special Character & Bracket Resilience**: Full `-LiteralPath` enforcement throughout orchestrator and execution engine, preventing PowerShell globbing failures on capture files containing brackets `[ ]` (e.g., `[DQ] [PD] Meet...`).
* **Runtime Telemetry & Container Auditing**: Explicitly logs script identity (`script_name` & `script_version`) along with Docker container metadata (`image`, `image_id`, `api_version`, `cudnn_version`, `status`) and Ollama service versions in `.log` and `.SUMMARY.md`.
* **Zero-Overhead Hardware Telemetry**: Collects CPU, RAM, and GPU hardware metrics via native CIM queries.

---

## 📁 Repository Structure

```text
WHISPER/
├── .github/
│   └── workflows/
│       ├── ci.yml                 # PSScriptAnalyzer linting + Pester 5/6 unit tests
│       └── release.yml            # Automated GitHub releases on tag push
├── src/
│   ├── _MASTER_WHISPER.ps1        # Pure batch orchestrator
│   └── whisper-asr-service-docker.ps1 # Self-contained execution engine
├── config/
│   ├── config.default.json        # Base defaults (Tracked in Git)
│   ├── config.local.json.example  # Template for machine overrides
│   └── config.local.json          # Machine overrides (Git-ignored)
├── tests/
│   ├── _MASTER_WHISPER.Tests.ps1  # Unit tests for batch orchestration
│   └── whisper-asr-service-docker.Tests.ps1 # Unit tests for engine, config & timecodes
├── docs/
│   ├── ARCHITECTURE.md          # End-to-end technical architecture & diagrams
│   ├── WORKFLOW_GUIDE.md        # Operations, troubleshooting & developer runbook
│   └── adr/                     # Architecture Decision Records (0001–0015)
├── macos/                       # macOS Apple Silicon (M2 Max) native GPU backend
│   ├── whisperx_mlx_server.py   # Hybrid FastAPI server (Metal MLX + MPS PyTorch)
│   ├── setup_macos.sh           # Automated environment and virtualenv bootstrap
│   ├── convert_kinit_sk_to_mlx.py # Model conversion utility for Slovak weights
│   ├── requirements-macos.txt   # Pinned Apple Silicon dependencies
│   └── .env.example             # Hugging Face token template
├── CHANGELOG.md                 # Release history and changelog (v01.00 to v07.00)
├── AGENTS.md                    # Operating guidelines for AI coding agents
├── GEMINI.md                    # Project rules & manual Git policies
├── PSScriptAnalyzerSettings.psd1 # Linter rule definitions
└── README.md                    # Project overview & documentation
```

---

## 🏷️ Filename Naming Convention

Name your audio/video files using the standard pattern:
```text
[title].[LANG]-[PROFILE][SPEAKERS].[ext]
```

### Pattern Components:
* **`LANG`** (2 letters, optional): `CS` (Czech), `SK` (Slovak), `EN` (English), or omitted for Whisper auto-detection.
* **`PROFILE`** (1 letter, optional):
  * `P` $\rightarrow$ `phone` profile (narrowband speech optimization)
  * `M` $\rightarrow$ `meeting` profile (dynamic acoustic normalization)
  * `D` $\rightarrow$ `distant` profile (compression & noise suppression)
  * `H` $\rightarrow$ `hallway` profile (reverberant corridor audio with Slovak model)
  * `E` $\rightarrow$ `echoed` profile (universal reverberant audio with anti-hallucination decoding)
* **`SPEAKERS`** (integer, optional): Number of distinct diarized speakers (sets `min_speakers` and `max_speakers`).

### Examples:
* `2026-04-14_O2-Rozhovor.CS-P2.m4a` $\rightarrow$ Czech, Phone profile, 2 speakers.
* `TeamSync_Sprint42.SK-M5.mp3` $\rightarrow$ Slovak, Meeting profile, 5 speakers.
* `Corridor_CCTV_Sample.SK-E2.mp4` $\rightarrow$ Slovak, Echoed profile, 2 speakers.
* `Conference_Keynote.EN-D1.flac` $\rightarrow$ English, Distant profile, 1 speaker.
* `voice_memo.mp4` $\rightarrow$ Defaults to Phone profile with auto language detection.

---

## 🚀 Quick Start

### Platform Option A: Windows 11 (NVIDIA CUDA via Docker)
1. **Prerequisites**: PowerShell 7+, FFmpeg in PATH, Docker Desktop (WhisperX on port 9000).
2. **Local Overrides**: Copy `config\config.local.json.example` to `config\config.local.json` if needed.
3. **Run Batch Transcription**:
   ```powershell
   pwsh -File .\src\_MASTER_WHISPER.ps1 -InputFolder "D:\Recordings\Meetings"
   ```

### Platform Option B: macOS Apple Silicon (M1/M2/M3/M4 Native Metal GPU)
1. **One-Command Setup**:
   ```bash
   export HF_TOKEN="hf_your_token_here"
   ./macos/setup_macos.sh
   ```
2. **Start Native GPU Whisper Service**:
   ```bash
   python ./macos/whisperx_mlx_server.py
   ```
3. **Run Batch Transcription**:
   ```powershell
   pwsh -File ./src/_MASTER_WHISPER.ps1 -InputFolder ~/Recordings -SkipDJI
   ```

---

### Selective LLM Execution Switches (Cross-Platform)

### 4. Run Single File Transcription
```powershell
pwsh -File .\src\whisper-asr-service-docker.ps1 `
    -FilePath "D:\Recordings\cctv_sample.SK-E2.mp4" `
    -Profile echoed `
    -Language sk `
    -MinSpeakers 2 `
    -MaxSpeakers 2 `
    -GenerateMode both
```

### 5. CLI Help & Switch Discovery
Quickly inspect supported switches, parameter aliases, and filename tagging conventions:
```powershell
# Full parameter reference & profile table
Get-Help .\src\_MASTER_WHISPER.ps1 -Full

# Copy-pasteable syntax examples
Get-Help .\src\_MASTER_WHISPER.ps1 -Examples

# Fast terminal syntax trigger
.\src\_MASTER_WHISPER.ps1 -?
```
*💡 **Tip**: In PowerShell 7+, type `.\src\_MASTER_WHISPER.ps1 -` and press <kbd>Tab</kbd> or <kbd>Ctrl</kbd>+<kbd>Space</kbd> for interactive auto-completion of all switches and aliases.*

### 6. Inspect Execution Telemetry & Container Metadata
Every run generates a structured JSON execution log (`.log`) capturing script version, Docker container metadata, hardware specs, and performance metrics:
```powershell
Get-Content .\Recordings\meeting.WHISPER.*.log | ConvertFrom-Json | Select-Object script_name, script_version, container_information
```

---

## 🧪 Testing & Quality Assurance

Run Pester unit tests:
```powershell
Invoke-Pester -Path ./tests -Output Detailed
```

---

## 🔒 Git & Contribution Policy

> [!IMPORTANT]
> All commits, merges, and pushes are performed manually by the human developer via **GitHub Desktop**. AI agents are strictly forbidden from running automated `git commit` or `git push` commands.