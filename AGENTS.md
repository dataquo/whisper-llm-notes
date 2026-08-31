# AGENTS.md - AI Agent Operating Context & Instructions

This document provides system context, architectural guidelines, testing commands, and operational constraints for AI coding agents (such as Antigravity, Gemini, Claude, and Copilot) working in the **WHISPER** repository.

---

## 1. Project Purpose & Architecture

WHISPER is a resilient, batch audio transcription and AI summarization pipeline. It combines:
1. **PowerShell 7+** for orchestrating pipelines and manipulating file formats in RAM.
2. **FFmpeg** for profile-based digital signal processing (DSP) and broadcast loudness normalization (-16 LUFS).
3. **WhisperX (Docker)** on port 9000 for ASR, word timestamps, and multi-speaker diarization.
4. **LM Studio** on port 1234 / remote for detailed structured meeting notes (`.NOTES.md`).
5. **Ollama** on port 11434 for executive summaries (`.SUMMARY.md`).

---

## 2. Directory Layout & Key Files

```text
WHISPER/
├── src/
│   ├── _MASTER_WHISPER.ps1        # Batch orchestrator: scans folders, detects missing outputs
│   └── whisper-asr-service-docker.ps1 # Engine: FFmpeg DSP -> WhisperX -> Multi-format -> LLM
├── config/
│   ├── config.default.json        # Tracked base settings, filter chains, and default models
│   └── config.local.json.example  # Untracked local override template
├── tests/
│   ├── _MASTER_WHISPER.Tests.ps1  # Unit tests for parameter extraction & checks
│   └── whisper-asr-service-docker.Tests.ps1 # Unit tests for timecodes & format converters
├── docs/
│   ├── ARCHITECTURE.md          # End-to-end technical architecture & diagrams
│   ├── WORKFLOW_GUIDE.md        # Operations & troubleshooting guide
│   └── adr/                     # Architectural Decision Records (0001-0008)
├── .github/workflows/
│   ├── ci.yml                   # PSScriptAnalyzer + Pester 5/6 CI pipeline
│   └── release.yml              # Automated release packaging on tag push
├── CHANGELOG.md                 # Full release history from v01.00 to v06.01
├── GEMINI.md                    # Active rules (NO automatic git commits/pushes)
└── README.md                    # Project overview & quickstart
```

---

## 3. Strict Operating Rules for AI Agents

> [!CAUTION]
> **Git Operations Policy (Human-in-the-Loop)**
> * The AI agent must **NEVER** run `git commit`, `git push`, `git tag`, `git merge`, or `git reset`.
> * All staging, committing, and pushing must be performed manually by the human user via **GitHub Desktop**.
> * **Commit Message Policy**: The AI agent must generate a formatted **Commit Summary** (title) and **Commit Description** (body) for GitHub Desktop **ONLY when explicitly requested by the user**. Do NOT generate commit messages automatically after every change.

---

## 4. Architectural Guidelines & Invariant Rules

### A. Clean Architectural Decoupling
* **`src/_MASTER_WHISPER.ps1` (Pure Batch Orchestrator)**:
  * Responsible **ONLY** for:
    1. Scanning input directories for media files (`.m4a`, `.flac`, `.mp4`, `.mp3`).
    2. Extracting parameters from filename conventions (`.LL-X#`).
    3. Checking which transcript/summary files (`.json`, `.txt`, `.srt`, `.tsv`, `.vtt`, `.NOTES.md`, `.SUMMARY.md`) are missing or empty.
    4. Passing parameters and delegating execution to `whisper-asr-service-docker.ps1`.
  * Supports selective generation flags: `-OnlyOllama`, `-OnlyLMStudio`, `-DisableLLM`.
  * **Rule**: NEVER add Docker commands, container health checks, FFmpeg execution, or configuration loading into `_MASTER_WHISPER.ps1`. Keep it clean and lightweight (~220 lines).
* **`src/whisper-asr-service-docker.ps1` (Self-Contained Execution Engine)**:
  * Responsible for all single-file processing:
    1. Loading and layering configuration (`Get-PipelineConfig`).
    2. Managing container health and startup (`Ensure-WhisperContainerRunning`).
    3. Running FFmpeg audio preprocessing with mono downmixing (`-ac 1`) and notch EQ.
    4. Calling WhisperX API and generating secondary formats in RAM with deduplication.
    5. Flushing GPU VRAM via container restart (`Restart-WhisperContainer`).
    6. Calling LLM summarization services (Ollama & LM Studio) with context-aware reconstruction prompts.
* **Single Source of Truth**:
  * All production PowerShell scripts live exclusively inside `src/`.
  * **Rule**: NEVER create duplicate copies or mirror scripts in the repository root (`WHISPER/`).

### B. Deep Configuration Layering & Dynamic Resolution
* **No Guessing / No Hardcoded Heuristics**: Never write ad-hoc guessing loops or heuristic fallbacks for container names, ports, or model endpoints.
* **`config/config.default.json` (Tracked in Git)**:
  * Contains official repository defaults: baseline models (`large-v3`, `gemma3:4b`), audio profile filter chains, default timeouts, and standard container name (`whisper-asr-service`).
* **`config/config.local.json` (Untracked, in `.gitignore`)**:
  * Used for machine-specific overrides (e.g. developer laptop container `whisperx-api`, remote LM Studio host, or custom models).
* **Deep Merging Requirement**:
  * `Get-PipelineConfig` loads `config.default.json` and recursively overlays `config.local.json`.
  * **Rule**: When reading or editing config logic, always ensure deep property merging is maintained so that partial local overrides do not wipe out baseline filter chains, timeouts, or model settings.
* **Dynamic Profile & Logging Binding**:
  * The engine and logger (`New-TranscriptionLog`) resolve all profile properties dynamically from `$AppConfig.profiles.$Profile` rather than using static hardcoded switch blocks.

### C. Language Guards & ASR Decoding Guidelines
* **Language-Specific Model Guard**: Fine-tuned models targeting a single language (such as `whisper-large-v3-kinit-sk-ct2` for Slovak) must NEVER be applied to other languages (`cs`, `en`, etc.). The engine automatically intercepts non-matching languages and redirects them to multilingual `large-v3`.
* **Reverberation & CCTV Decoding Constraints**: On muffled or reverberant audio, standard beam search can generate severe hallucination loops. Always utilize greedy search (`beam_size=1`), `condition_on_previous_text=false`, and `repetition_penalty=1.2` (as configured in the `echoed` profile).

---

## 5. Coding & Quality Standards

1. **Encoding**: All file writes containing text or transcript content must use clean UTF-8 without BOM:
   ```powershell
   $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
   [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
   ```
2. **Pester Unit Tests**:
   * All new functions, parameter additions, or architectural changes must include unit tests in `tests/`.
   * Use Pester 5/6 standard hyphenated assertions: `Should -Be`, `Should -BeTrue`, `Should -BeFalse`, `Should -BeNullOrEmpty`, `Should -Match`.
   * In `BeforeAll`, register helper functions into the global scope (`function global:FunctionName`) so they are accessible to Pester test blocks.
3. **PSScriptAnalyzer**:
   * Ensure changes pass `Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1` with zero Errors.
4. **CIM over WMI**:
   * Always use `Get-CimInstance` instead of deprecated `Get-WmiObject` to prevent PowerShell 7 implicit remoting freezes.

---

## 6. Verification Commands

Before concluding any refactoring or feature implementation, run the test suite:
```powershell
# Run Pester Unit Tests
Invoke-Pester -Path ./tests -Output Detailed

# Run PowerShell Linter
Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

---

## 7. How to Add New Audio Profiles

1. Add profile settings to [config/config.default.json](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/config/config.default.json) under `"profiles"`.
2. Update the filename parameter extractor in [src/_MASTER_WHISPER.ps1](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/src/_MASTER_WHISPER.ps1) and [src/whisper-asr-service-docker.ps1](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/src/whisper-asr-service-docker.ps1).
3. Add corresponding test cases in [tests/_MASTER_WHISPER.Tests.ps1](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/tests/_MASTER_WHISPER.Tests.ps1) and [tests/whisper-asr-service-docker.Tests.ps1](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/tests/whisper-asr-service-docker.Tests.ps1).
4. Update documentation in [docs/ARCHITECTURE.md](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/docs/ARCHITECTURE.md).