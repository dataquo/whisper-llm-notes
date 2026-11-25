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
│   └── adr/                     # Architectural Decision Records (0001-0018)
├── .github/workflows/
│   ├── ci.yml                   # PSScriptAnalyzer + Pester 5/6 CI pipeline
│   └── release.yml              # Automated release packaging on tag push
├── CHANGELOG.md                 # Full release history from v01.00 to v07.03
├── GEMINI.md                    # Active rules (NO automatic git commits/pushes)
├── LICENSE                      # GNU AGPL-3.0
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
    1. Scanning input directories for media files (`.m4a`, `.flac`, `.mp4`, `.mp3`, `.webm`).
    2. Orchestrating external video pre-processing (`..\DJI\convert_DJI_videos_with_MetaData.ps1`) via `Get-DjiScriptPath` and `Invoke-DjiConversion`, dynamically selecting the platform hardware decoding profile (`special-quality-hw-opt-Apple_M2` on macOS vs `special-quality-hw-dec-cuda` on Windows), configurable via `-DjiScene` (alias `-DjiProfile`).
    3. Suppressing duplicate converted video outputs (`*.CRF-*_LIBSVT-AV1*.webm`) when original source media exists.
    4. Extracting parameters from filename conventions (`.LL-X#`), with transcode suffix normalization.
    5. Checking which transcript/summary files (`.json`, `.txt`, `.srt`, `.tsv`, `.vtt`, `.NOTES.md`, `.SUMMARY.md`) are missing or empty.
    6. Passing parameters and delegating execution to `whisper-asr-service-docker.ps1`.
  * Supports selective generation flags: `-OnlyOllama`, `-OnlyLMStudio`, `-DisableLLM`, `-SkipDJI`.
  * **Rule**: NEVER add Docker commands, container health checks, FFmpeg execution, or configuration loading into `_MASTER_WHISPER.ps1`. External script execution must be strictly delegated via candidate resolution and guarded by bypass switches. Keep it clean and lightweight.
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
* **Anti-Hallucination ASR Decoding Invariant (`condition_on_previous_text=false`)**: In environments with low SNR, quiet meeting pauses, or muted screen recording microphones, dynamic normalization (`dynaudnorm`) elevates ambient noise floor. Whisper's autoregressive decoder must NEVER condition on previous text in `meeting` profiles (`condition_on_previous_text: false`), as prompt-conditioning triggers infinite cascades of polite hallucinated phrases (`"Thank you"`, `"Thanks for watching"`). Furthermore, Stage 0 VAD enforces an active speech duration floor (`total_speech >= 0.5s`), and Stage 2 forced alignment prunes unaligned phantom tokens upon alignment backtrack failures (ADR 0017).

### D. Speaker Diarization, Receptive Boundary Priming & Timestamp Integrity
* **No Script-Level Speaker Backfilling**: Never write post-hoc heuristics or guessing loops in PowerShell to reassign or backfill speaker IDs. Diarization must be generated faithfully by WhisperX and PyAnnote.
* **Sub-Second Timestamp Compensation (`lead_in_silence_seconds`)**: When padding audio in FFmpeg (e.g. `adelay` to prime PyAnnote's temporal receptive window), always ensure the execution engine applies `Adjust-TranscriptTimestamps` to subtract the offset with a 0.0s floor clamp across segments, words, and word-segments before generating any secondary formats.
* **Regex Encoding Safety**: All regex pattern cleaning (such as in `Clean-TranscriptText`) must use explicit unicode escape sequences (e.g. `\u2013\u2014`) rather than literal em-dashes to avoid stripping Czech/Slovak diacritics under Windows default code pages.

### E. Script Versioning & Runtime Telemetry Auditing
* **Canonical Script Version**: Maintain explicit constant `$ScriptVersionNumber = "v07.03"` and `$ScriptName = "whisper-asr-service-docker.ps1"`. Never re-introduce filename-based versioning for scripts inside `src/`.
* **Telemetry Logging Invariants**: Both initial logs (`New-TranscriptionLog`) and completion summaries (`Write-CompletionSummary`) must write separate `"script_name"` and `"script_version"` properties.
* **Container Metadata Forwarding (`Get-WhisperContainerMetadata`)**: Always forward `$PipelineConfig` into container inspection so machine-level overrides (`config.local.json`) are respected. Maintain the 3-tier inspection strategy (configured Docker inspect $\to$ candidate fallback $\to$ HTTP `/openapi.json`) to guarantee zero-null telemetry logs.
* **LLM Service Version Auditing**: When integrating LLM summarization endpoints, query `/api/version` (guarded by a $\le 2\text{s}$ timeout) and record service version rows in markdown parameter tables.
* **Silence & Zero-Speech Pipeline Invariants**: Never treat empty segment arrays (`$ApiResult.segments.Count -eq 0`) as fatal script aborts. Ensure empty downstream transcript files are generated gracefully so batch directories do not enter infinite reprocessing loops (ADR 0013).
* **Untagged Filename Warnings**: Maintain high-visibility red warnings (`-ForegroundColor Red`) whenever a media file lacks profile tagging or explicit CLI parameters.

### F. Cross-Platform Execution & macOS Apple Silicon Invariants
* **Dual-Platform Architecture**: The codebase supports both Windows 11 (NVIDIA CUDA via Docker) and macOS Apple Silicon (M1/M2/M3/M4 via native `macos/whisperx_mlx_server.py`).
* **Platform-Agnostic Binaries & Paths**: Never hardcode `.exe` extensions or literal backslashes (`\`). Always resolve binaries via `Get-PlatformBinaryName` and combine paths using `Join-Path`.
* **Curl Multipart Quoting & UNC Forward-Slash Normalization**: When passing file paths to `curl` multipart arguments (`-F`), always enclose the path in escaped double-quotes (`-F "audio_file=@`"$curlUploadFile`""`) AND normalize all backslashes to forward slashes (`$curlUploadFile = $TempProcessedFile -replace '\\', '/'`). On Windows, unquoted paths containing commas cause multi-file delimiter splitting, while Windows `curl.exe` argument unescaping corrupts UNC backslashes (`@"\\` $\to$ `\server\share`), both triggering `curl: (26) Failed to open/read local data from file`. Win32 APIs and curl natively support forward slashes for UNC shares (`//server/share/...`).
* **PyTorch 2.6+ Checkpoint Safety**: In Python services, PyTorch 2.6 defaults `torch.load` to `weights_only=True`. Always register safe globals (`omegaconf.listconfig.ListConfig`, `dictconfig.DictConfig`, etc.) and enforce `weights_only=False` fallback on trusted local checkpoints to avoid breaking Silero VAD and PyAnnote Diarization.
* **Hugging Face Classic Read Token Requirement**: PyAnnote 3.1 dynamically loads unlisted sub-dependencies (`pyannote/wespeaker-voxceleb-resnet34-LM`). Narrow Fine-Grained tokens fail with `'NoneType' object has no attribute 'to'`. Always require a **Classic Read Token** placed in canonical `WHISPER/macos/.env`, with accepted terms on both `pyannote/speaker-diarization-3.1` and `segmentation-3.0`.
* **`native-mlx` Container Lifecycle**: When `$PipelineConfig.whisper_service.docker_container_name` is set to `"native-mlx"`, the engine skips Docker CLI calls (`docker inspect`, `docker restart`), retrieves container metadata via `GET /openapi.json`, and flushes Unified Memory via `POST /gc`.
* **Dedicated macOS Tests**: Cross-platform abstractions and `native-mlx` workflows are tested in `tests/macos-crossplatform.Tests.ps1`.

### G. FFmpeg Audio Demuxing, Video Bypass & Resilience Invariants
* **Video Stream Bypass (`-vn`)**: Always specify `-vn` prior to audio filter processing in execution engine commands. Video streams in high-resolution recordings (1080p, 1440p/2K, 4K) must never be demuxed or decoded into RAM during audio extraction.
* **Corrupted Packet & Cutfile Demuxer Tolerance**: Prepend `-err_detect ignore_err -fflags +genpts+igndts+discardcorrupt` to input arguments (`-i`). This prevents fatal demuxer abortions and 90+ second EOF freezing on truncated cutfile media (`.cutfile.`) or external storage read timeouts (`/Volumes/...`).
* **Audio Profile & Normalization Invariants**: Audio DSP filters (`dynaudnorm`, `speechnorm`, `loudnorm`) and MP3 compression (`libmp3lame`) execute exclusively on a single CPU core (GPU utilization is expected to be 0%). Never strip loudness normalization (`-16 LUFS`, `TP=-1.5`) or profile filter chains to gain raw conversion speed; acoustic normalization is essential for ASR transcription stability and PyAnnote diarization accuracy (ADR 0016).

### H. Public Release Standards, Privacy Neutralization & Dual-Licensing Invariants
* **Public Repository Identity**: The canonical public project name is **`whisper-llm-notes`** (`https://github.com/dataquo/whisper-llm-notes`).
* **Privacy & Network Share Sanitization**: All file paths in documentation, test suites, and script comments must utilize vendor-neutral mock roots (`\\server\share\...` or `C:\Users\test,user\...`). Never commit specific internal storage hostnames, private network directories, or local usernames.
* **Dual-Licensing Model (GNU AGPL-3.0 + Commercial)**: The repository is published under GNU Affero General Public License v3.0 (AGPL-3.0). DataQuo retains sole commercial licensing authority for proprietary, closed-source SaaS exemptions. Community contributions and changes must never introduce licenses that infringe upon DataQuo's dual-licensing rights.
* **Tracked Dependencies Invariant**: `.gitignore` must retain the negative pattern `!macos/requirements*.txt` to ensure external contributors cloning the repo receive all prerequisites for `setup_macos.sh`.

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
5. **Comment-Based Help (CBH) & Parameter Discoverability**:
   * All parameter additions, switches, or aliases in `src/` must maintain full Comment-Based Help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`).
   * Filename tagging conventions and DSP profile additions must be mirrored in `.DESCRIPTION` so `Get-Help` and `-?` remain the single source of CLI truth.

6. **Special Characters & Literal Paths**:
   * Always use `-LiteralPath` (never positional `-Path`) on all PowerShell filesystem cmdlets (`Test-Path`, `Get-Content`, `Move-Item`, `Get-Item`, `Remove-Item`, `Set-Content`) to avoid wildcard pattern globbing failures on bracketed filenames (e.g. `[DQ] [PD] Meeting...`). See ADR 0012.

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