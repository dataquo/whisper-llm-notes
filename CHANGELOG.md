# Changelog - WHISPER

All notable changes to the WHISPER project are documented in this file. The project follows [Semantic Versioning](https://semver.org/).

---

## [v06.05] - 2026-11-07
### Added
* **Architecture Decision Record 0013** (`docs/adr/0013-empty-speech-vad-silence-and-untagged-profile-alerts.md`):
  * Comprehensive technical analysis of silent/no-speech audio handling, PyAnnote VAD zero-segment behavior, Hugging Face Transformers pipeline iterator crashes, and visual warning notification strategies for untagged media.
* **Prominent Red Warning for Untagged Profiles**:
  * Both `src/_MASTER_WHISPER.ps1` and `src/whisper-asr-service-docker.ps1` now emit a high-visibility terminal warning in bright red (`-ForegroundColor Red`) whenever a file lacks a profile tag or explicit CLI parameter, clearly notifying users that the default `phone` profile and auto-detect language are being applied and recommending standard `.LL-X#` naming conventions.
* **Graceful Zero-Speech & Silence Resilience in PowerShell Pipeline**:
  * Replaced falsy array check `if (-not $ApiResult.segments)` with strict null checking `if ($null -eq $ApiResult.segments)` in `src/whisper-asr-service-docker.ps1`.
  * When no active speech or segments are detected (`segments.Count -eq 0`), the engine logs a warning and generates valid blank secondary formats (`.txt`, `.srt`, `.vtt`, `.tsv`, `.NOTES.md`, `.SUMMARY.md`), preventing fatal script terminations and infinite retry loops on subsequent folder scans.
* **Expanded Pester Regression Test Suite**:
  * Added unit test assertions in `tests/_MASTER_WHISPER.Tests.ps1` validating that untagged files are flagged with `IsDefault = $true` while tagged filenames maintain `IsDefault = $false` (36/36 tests passing).

### Changed
* **Upstream WhisperX VAD Silence Guard (`whisperx/asr.py`)**:
  * Patched `whisperx/asr.py` inside the Docker image `learnedmachine/whisperx-asr-service:latest` to guard against zero VAD segments (`if len(vad_segments) == 0: return {'segments': [], 'language': language}`).
  * Resolves fatal `IndexError: list index out of range` in Transformers `Pipeline.__call__` when audio contains no detected speech under narrow bandpass filtering.
* **Canonical Version Bump to v06.05**:
  * Updated `$ScriptVersionNumber = "v06.05"` in `src/whisper-asr-service-docker.ps1`.
  * Updated Comment-Based Help version metadata to `v06.05` in `src/_MASTER_WHISPER.ps1` and `src/whisper-asr-service-docker.ps1`.
  * Updated documentation across `README.md`, `docs/ARCHITECTURE.md`, `docs/WORKFLOW_GUIDE.md`, `AGENTS.md`, and `GEMINI.md`.

---

## [v06.04] - 2026-11-07
### Added
* **Architecture Decision Record 0012** (`docs/adr/0012-literalpath-bracket-filename-resilience.md`):
  * Comprehensive technical analysis of PowerShell provider wildcard globbing on bracketed filenames (`[...]`), evaluating string escaping vs. filename sanitization vs. idiomatic `-LiteralPath` enforcement.
* **Special Character & Bracket Filename Resilience (`-LiteralPath`)**:
  * Enforced `-LiteralPath` across all PowerShell provider cmdlets (`Test-Path`, `Get-Content`, `Move-Item`, `Get-Item`, `Remove-Item`) in `src/_MASTER_WHISPER.ps1` and `src/whisper-asr-service-docker.ps1`.
  * Guarantees seamless handling of real-world meeting recordings containing literal brackets (e.g., `2026-11-05 [DQ] [PD] Meet...`), avoiding false "Processed audio file not found" fatal exits and missing FFmpeg log warnings.
* **Expanded Pester Regression Test Suite**:
  * Added unit test in `tests/_MASTER_WHISPER.Tests.ps1` validating that paths containing literal square brackets (`[ ]`) correctly detect missing and existing markdown summaries (`.NOTES.md`, `.SUMMARY.md`) via `Get-MissingMdFiles` (35/35 tests passing).

### Changed
* **Canonical Version Bump to v06.04**:
  * Updated `$ScriptVersionNumber = "v06.04"` in `src/whisper-asr-service-docker.ps1`.
  * Updated Comment-Based Help version metadata to `v06.04` in `src/_MASTER_WHISPER.ps1`.
  * Updated `README.md`, `docs/ARCHITECTURE.md`, `docs/WORKFLOW_GUIDE.md`, `AGENTS.md`, and `GEMINI.md`.

## [v06.03] - 2026-09-08
### Added
* **Architecture Decision Record 0011** (`docs/adr/0011-runtime-telemetry-and-container-metadata-auditing.md`):
  * Documents the evaluation of runtime pipeline versioning, container telemetry auditing, and failover discovery strategies.
* **Architecture Decision Record 0010** (`docs/adr/0010-telephone-diarization-boundary-silence-and-alignment.md`):
  * Comprehensive technical root cause analysis of telephone audio diarization, PyAnnote sliding convolutional receptive window, Wav2Vec2 forced alignment silence-stretching, and architectural alternatives.
* **Docker Container & Whisper Service Telemetry in Transcription Logs**:
  * Added `Get-WhisperContainerMetadata` helper function in `src/whisper-asr-service-docker.ps1` to capture `container_name`, `image`, `image_id`, `api_version`, `cudnn_version`, and `status` in `New-TranscriptionLog` and `Write-CompletionSummary`.
  * **Configuration Forwarding**: Passes loaded `$AppConfig` directly into logging functions, ensuring machine-specific container names in `config.local.json` (such as `whisperx-api`) are inspected instead of hardcoded defaults.
  * **Dynamic Candidate Fallback**: If the configured container fails inspection, automatically scans active candidate containers (`whisperx-api`, `whisper-asr-service`) before engaging HTTP fallback.
  * **HTTP Fallback**: Queries `$ApiUrl/openapi.json` to extract `api_version` and set status to `"online"` when running on remote Docker hosts without CLI access.
* **Ollama Service Version in Markdown Summaries**:
  * Dynamically queries Ollama's `/api/version` (guarded by a 2-second timeout) and appends `| Service Version | Ollama <version> |` to the `AI Processing Information` table in `.SUMMARY.md`.
* **Lead-in Silence Diarization Priming (`lead_in_silence_seconds`) for `phone` Profile**:
  * Automatically prepends 1.5 seconds of silence via FFmpeg (`adelay=1500:all=1`) when preprocessing phone calls to prime PyAnnote's temporal receptive field.
  * Added `Adjust-TranscriptTimestamps` helper to subtract the 1.5s offset from all segment, word, and word-segment timestamps (clamping to 0.0s, rounding to 3 decimals), ensuring 100% timecode synchronization across all generated formats (`.json`, `.txt`, `.srt`, `.vtt`, `.tsv`).
* **Expanded Test Suite**:
  * Added unit tests covering canonical version resolution, legacy filename backward-compatibility, container metadata schema completeness, and lead-in silence compensation (34/34 passing).

### Changed
* **Explicit Script Name & Version in Transcription Logs**:
  * Replaced legacy regex-only `$ScriptVersion` with canonical `$ScriptVersionNumber = "v06.03"` and `$ScriptName = "whisper-asr-service-docker.ps1"`.
  * Separated `"script_version"` into distinct `"script_name"` and `"script_version"` fields in `.log` outputs, eliminating the unversioned fallback string.
* **Markdown Table Formatting**:
  * Corrected column separator count across `.SUMMARY.md` and `.NOTES.md` AI Processing Information tables from 3 columns to 2 columns (`| :--- | :--- |`).
* **Telephone Audio Bandwidth Calibration for `phone` Profile**:
  * Finalized sharp bandpass (`200–3500 Hz`) with speech normalization (`speechnorm=e=4:r=0.0001:l=1`) and broadcast loudness normalization (`loudnorm=I=-16:TP=-1.5:LRA=11`) to maintain clear acoustic differentiation from wideband meeting profiles (`80–8000 Hz`).
* **Diacritic & Encoding Guard**:
  * Enhanced `Clean-TranscriptText` regex with unicode escape literals (`\u2013\u2014`) and explicit UTF-8 without BOM streams (`[System.IO.File]::ReadAllText($Path, $Utf8NoBom)`) to protect Czech and Slovak diacritics against character corruption.

## [v06.02] - 2026-09-01
### Added
* **Architecture Decision Record 0009** (`docs/adr/0009-comment-based-help-and-cli-discovery.md`): Documents the design evaluation between automatic console banner injection, custom `-Help` switches, and idiomatic PowerShell Comment-Based Help (CBH).
* **Comprehensive Comment-Based Help (CBH)** in `src/_MASTER_WHISPER.ps1`:
  * Detailed `.DESCRIPTION` section breaking down the `[name].[LL]-[X][#].[ext]` filename parameter tagging convention (Language codes, DSP profile letters `P`/`M`/`D`/`H`/`E`, speaker count diarization).
  * Explicit documentation for all parameters (`-InputFolder`, `-ConfigPath`, `-DisableLLM`, `-OnlyOllama`, `-OnlyLMStudio`) and their case-insensitive aliases.
  * Four practical, copy-pasteable `.EXAMPLE` blocks accessible via `Get-Help .\src\_MASTER_WHISPER.ps1 -Examples`.
* **Standard PowerShell Parameter Discovery**:
  * Seamless integration with native `Get-Help`, `Get-Help -Full`, `Get-Help -Examples`, and `.\src\_MASTER_WHISPER.ps1 -?`.
  * Interactive PowerShell 7+ Tab and <kbd>Ctrl</kbd>+<kbd>Space</kbd> parameter auto-completion.

### Changed
* **Documentation Modernization**:
  * Updated `README.md`, `docs/ARCHITECTURE.md`, and `docs/WORKFLOW_GUIDE.md` to reflect `v06.02` and include parameter discovery runbooks.
  * Updated `AGENTS.md` and `GEMINI.md` to maintain Comment-Based Help integrity across future parameter refactoring.

---

## [v06.01] - 2026-09-01
### Added
* **Architecture Decision Record 0008** (`docs/adr/0008-reverberant-hallway-profiles-and-acoustic-reconstruction.md`).
* **Dedicated Reverberant Profiles (`hallway` & `echoed`)**:
  * Added `hallway` (`.SK-H#` / `HALLWAY-NORM_HP-LP-DN-EQ`) with Slovak fine-tuned model (`whisper-large-v3-kinit-sk-ct2`).
  * Added `echoed` (`.SK-E#` / `ECHOED-NORM_HP-LP-DN-EQ`) with OpenAI `large-v3`, greedy search (`beam_size=1`), and repetition penalty (`1.2`) for universal echo suppression.
  * Specialized 5-stage FFmpeg filter chain: High-Pass (220 Hz), Low-Pass (3700 Hz), FFT Spectral Denoise (`afftdn` -14 dB), 380 Hz Resonant Notch Equalizer (`equalizer`), and EBU R128 Loudness Normalization (-16 LUFS).
* **Tuned ASR Decoding Query Strings**:
  * Configured `beam_size=1` (greedy search), `condition_on_previous_text=false`, `repetition_penalty=1.2`, and `no_repeat_ngram_size=3` to eliminate looping hallucinations on low-SNR recordings.
* **Automatic Language Guard**:
  * Enforces that language-specific fine-tuned models (e.g. `kinit-sk`) are dispatched strictly when `Language == 'sk'`.
  * Automatically falls back to standard multilingual `large-v3` for Czech (`cs`) and English (`en`) recordings.
* **Context-Aware LLM Post-Reconstruction**:
  * Added specialized acoustic reconstruction prompt instructions into LM Studio (`.NOTES.md`) and Ollama (`.SUMMARY.md`) templates when transcribing reverberant profiles.
* **Selective LLM Generation Switches**:
  * Added `-OnlyOllama` (aliases: `-OnlyOlama`, `-OllamaOnly`) to generate exclusively `.SUMMARY.md` via Ollama.
  * Added `-OnlyLMStudio` (aliases: `-LMStudioOnly`, `-OnlyLM`) to generate exclusively `.NOTES.md` via LM Studio.
* **IP Camera Audio Optimization Guide**:
  * Documented recommended CCTV hardware settings (switching from 8 kHz G.711u to 16 kHz AAC, activating hardware Environmental Noise Filtering, and reducing microphone input volume to 60–70%).

### Fixed
* **Dynamic Parameter Logging**: Refactored `New-TranscriptionLog` and profile resolution in `whisper-asr-service-docker.ps1` to pull 100% dynamically from `$AppConfig.profiles`, eliminating hardcoded switch overrides and recording exact `ffmpeg_filters`, `audio_format`, and `model` in `.log` files.
* **Multi-Format Stutter Deduplication**: Enhanced `Clean-TranscriptText` to collapse consecutive duplicate phrase loops across `.txt`, `.srt`, `.vtt`, and `.tsv` outputs.
* **PowerShell Parameter Alias Conflict**: Removed case-redundant alias collision on `-OnlyLMStudio` that caused `MetadataError` in PowerShell 7+.
* **Expanded Test Suite**: Added Pester unit tests covering `echoed` (E) parameter parsing, language guard fallbacks, and `-OnlyOllama` / `-OnlyLMStudio` modes (29/29 passing).

---

## [v06.00] - 2026-08-30
### Added
* **Architecture Decision Record 0007** (`docs/adr/0007-unified-container-lifecycle-and-config-layering.md`).
* **Deep Configuration Layering (`Get-PipelineConfig`)**: Recursively overlays machine-specific `config/config.local.json` on top of `config/config.default.json` without losing baseline profile or model settings.
* **Deterministic Container Lifecycle Manager**:
  * `Ensure-WhisperContainerRunning`: Verifies container status via Docker CLI, starts stopped containers, and polls `/docs` or `/health` until the API is online.
  * `Restart-WhisperContainer`: Restarts the configured container post-transcription and upon CUDA OOM errors, waiting for API readiness before the next iteration.
* **`-DisableLLMs` Switch**: Added switch (aliases: `-DisableLLMs`, `-DisableLLM`, `-SkipLLM`, `-NoLLM`) to `_MASTER_WHISPER.ps1` and `whisper-asr-service-docker.ps1` to run pure WhisperX transcription without Ollama or LM Studio.
* **Multi-Channel Downmixing (`-ac 1`)**: Added explicit mono downmixing across all FFmpeg DSP profiles (`phone`, `meeting`, `distant`) to support 5.1/7.1 HE-AAC audio tracks.
* **Corrupt & Empty Audio File Detection**: Validates that intermediate preprocessed audio is `Length > 1024` bytes, preventing corrupt headers from causing downstream WhisperX API crashes.
* **Native CIM Hardware Telemetry**: Replaced deprecated `Get-WmiObject` with `Get-CimInstance` in `Get-SystemInfo`, eliminating a 57-second PowerShell 7 implicit remoting delay.

### Changed
* **Architectural Decoupling**: Streamlined `src/_MASTER_WHISPER.ps1` from ~480 to ~220 lines into a pure batch orchestrator, centralizing all container lifecycle, FFmpeg DSP, and API execution inside `src/whisper-asr-service-docker.ps1`.
* **Single Source of Truth**: Standardized on `src/` as the sole codebase location and purged duplicate root scripts.
* **AI Agent Git & Commit Rules**: Updated `AGENTS.md` and `GEMINI.md` to enforce commit message generation ONLY on explicit user request.
* **Expanded Test Suite**: Added Pester unit tests for configuration deep merging, audio file validity, and `-DisableLLMs` mode.

---

## [v5.6.1] - 2026-08-30
### Added
* Comprehensive Architecture Decision Records (`docs/adr/0001` through `0006`).
* Technical architecture specification (`docs/ARCHITECTURE.md`) and operational runbook (`docs/WORKFLOW_GUIDE.md`).
* Agent operating instructions (`AGENTS.md`) and project rules (`GEMINI.md`).
* Fixed Pester 5 test runner function scoping and assertion operators.

---

## [v5.6.0] - 2026-08-28
### Added
* Continuous Integration pipeline (`.github/workflows/ci.yml`) with PSScriptAnalyzer linting and Pester 5 unit tests.
* Release automation pipeline (`.github/workflows/release.yml`).
* Externalized hierarchical JSON configuration (`config/config.default.json` and `config/config.local.json.example`).
* Automated unit test suite (`tests/_MASTER_WHISPER.Tests.ps1` and `tests/whisper-asr-service-docker.Tests.ps1`).
* Repository hygiene files: `.gitignore`, `.gitattributes`, `PSScriptAnalyzerSettings.psd1`, and `README.md`.
* Reconstructed 28 historical Git commits and tags from legacy snapshot files.

### Changed
* Refactored `_MASTER_WHISPER.ps1` to dynamically resolve engine paths without hardcoded version strings.
* Decoupled WhisperX, Ollama, and LM Studio endpoints to load from configuration.

---

## [v05.06] - 2026-08-28
### Added
* Latest stability improvements and parameter extraction hardening.

---

## [v05.05] - 2026-07-19
### Added
* **VRAM Optimization Phase**: Dynamically detects active Ollama models loaded in GPU memory and unloads them (`ollama stop <model>`) between transcription iterations to ensure WhisperX has sufficient VRAM.

---

## [v05.04] - 2026-06-09
### Fixed
* Fixed bug where files were skipped when only ONE of `NOTES.md` or `SUMMARY.md` was missing due to strict AND logic.
* Added `Get-MissingMdFiles` helper function to independently evaluate missing markdown files.
### Added
* `GenerateMode` parameter (`both`, `notes`, `summary`) to selectively trigger only missing summary files without re-transcribing.

---

## [v05.03] - 2026-05-18
### Fixed
* Fixed false "Transcript incomplete" triggers in `_MASTER_WHISPER.ps1` for files with existing `.NOTES.md` and `.SUMMARY.md` files.

---

## [v05.02] - 2026-05-18
### Fixed
* Fixed performance metrics calculation bug that triggered even when audio transcription was skipped during format conversion.

---

## [v05.01] - 2026-05-13
### Added
* Dual AI summary architecture:
  * `NOTES.md`: Generated via LM Studio with detailed structured meeting notes.
  * `SUMMARY.md`: Generated via Ollama for concise executive summaries.
* Appended model and server metadata tables at the end of generated markdown files.

---

## [v05.00] - 2026-05-12
### Added
* Declarative filename parameter syntax: `file_name.LL-X#.EXT` (Language, Profile, Speaker Count).
* Automatic regex extraction in `Parse-FileNameParameters` and `Extract-ParametersFromFilename`.
* Enhanced prompt for detailed notes generation.

---

## [v04.08] - 2026-04-22
### Fixed
* Strict UTF-8 without BOM encoding (`[System.Text.UTF8Encoding]($false)`) across all file I/O to preserve Czech and Slovak diacritics.

---

## [v04.06] - 2026-04-22
### Added
* Real-Time Factor (RTF), Tokens Per Second (TPS), and Token Count performance telemetry.
* Replaced `curl.exe` with `Invoke-RestMethod` for LLM JSON payloads to avoid Windows `MAX_COMMAND_LINE` limits on large transcripts.

---

## [v04.05] - 2026-04-17
### Added
* Comprehensive system hardware telemetry logging (CPU cores, RAM modules, GPU driver, Motherboard, BIOS, Disks) to JSON log files.

---

## [v04.04] - 2026-04-14
### Added
* Structured execution and timing log files: `{basename}.WHISPER.YYYYMMDD-HHmmss.log`.

---

## [v04.03] - 2026-04-14
### Added
* Detected language extraction from WhisperX JSON for LLM summarization prompt consistency.

---

## [v04.02] - 2026-04-14
### Added
* Incremental processing skips: avoids redundant transcription if `.json` exists, generating remaining formats directly.
* Added `-DebugMode` switch.

---

## [v04.01] - 2026-04-14
### Changed
* Non-streaming Ollama API integration with structured markdown summary prompts.

---

## [v04.00] - 2026-04-14
### Added
* Initial Ollama AI transcript summarization integration using `gemma3:4b`.
* Initial `_MASTER_WHISPER.ps1` batch orchestrator.

---

## [v03.06] - 2026-04-14
### Added
* Conditional check to skip FFmpeg preprocessing when preprocessed `.wav` / `.mp3` already exists.

---

## [v03.05] - 2026-04-14
### Fixed
* Fixed `FFREPORT` environment variable parsing error and standardized FFmpeg log naming.

---

## [v03.04] - 2026-04-14
### Added
* Switchable WAV (PCM 16-bit) and MP3 (libmp3lame, 64kbps) audio preprocessing codecs.

---

## [v03.03] - 2026-04-14
### Added
* Profile-specific FFmpeg audio preprocessing pipelines (`phone`, `meeting`, `distant`) with broadcast loudness normalization (-16 LUFS, TP=-1.5dB).

---

## [v03.02] - 2026-04-13
### Fixed
* Explicit language parameter forwarding as URL query parameter to native WhisperX endpoint.

---

## [v03.01] - 2026-04-13
### Added
* Multi-speaker diarization support and native `/asr` WhisperX endpoint integration.
* Automated container restart to flush GPU VRAM between long transcription runs.

---

## [v03.00] - 2026-04-01
### Added
* UNC path support and progress bar visualization.

---

## [v02.00] - 2026-03-20
### Added
* Single-pass multi-format generation: requests verbose JSON once from GPU and reconstructs `.txt`, `.srt`, `.vtt`, and `.tsv` in RAM.

---

## [v01.00] - 2026-03-20
### Added
* Initial PowerShell transcription script with acoustic profiles (`meeting`, `phone`) and `curl.exe` integration.
