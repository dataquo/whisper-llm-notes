# Changelog - WHISPER

All notable changes to the WHISPER project are documented in this file. The project follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

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
