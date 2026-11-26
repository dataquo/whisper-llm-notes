# Antigravity Project Rules: whisper-llm-notes

## 🚫 Git Operations & Version Control Policy
* **NO AUTOMATIC COMMITS OR PUSHES**: The AI agent must **NEVER** run `git commit`, `git push`, `git tag`, `git merge`, or `git reset` commands.
* **MANUAL HUMAN CONTROL**: All staging, committing, and pushing must be performed manually by the user via GitHub Desktop.
* **READ-ONLY GIT PERMITTED**: The agent is only permitted to run read-only inspection commands (such as `git status` or `git diff`) when helpful for context.
* **COMMIT SUMMARY & DESCRIPTION ON REQUEST ONLY**: The AI agent must generate a formatted **Commit Summary** (subject line) and **Commit Description** (body) for GitHub Desktop **ONLY when explicitly requested by the user**. Do NOT include commit messages automatically after every change.

## 🏛️ Architectural Decoupling & Single Source of Truth
* **Single Source of Truth**: All PowerShell code lives exclusively in `src/`. Never create duplicate scripts in the root directory.
* **Orchestrator Separation**: `src/_MASTER_WHISPER.ps1` is **ONLY** a batch orchestrator (folder scanning, parameter parsing, output checking, and external companion script delegation). NEVER put Docker lifecycle, container management, FFmpeg DSP, or config loading into `_MASTER_WHISPER.ps1`.
* **External Pre-Processing & Duplicate Suppression**: Orchestrates `..\DJI\convert_DJI_videos_with_MetaData.ps1` via candidate resolution and bypass switch (`-SkipDJI`). Automatically selects platform-appropriate hardware decoding (`special-quality-hw-opt-Apple_M2` on macOS vs `special-quality-hw-dec-cuda` on Windows), configurable via `-DjiScene` (alias `-DjiProfile`). Automatically suppresses converted WebM outputs (`*.CRF-*_LIBSVT-AV1*.webm`) and intermediate `.mp3` files when original media or base transcripts exist, while isolating quarantine subfolders (`_TO_DELETE_`) to ensure fresh transcode batches are processed through Whisper without manual intervention (ADR 0019).
* **Companion Cleanup & Log Discrimination**: When coordinating with companion cleanup (`LogFolderValidateAndZip.ps1`), ExifTool metadata text dumps (`---- ExifTool ----`) must be archived to category ZIPs, while genuine Whisper ASR `.txt` transcripts are preserved in the source folder whenever companion formats (`.json`, `.NOTES.md`, etc.) exist. Never rely on broad `.mp4` presence in `_TO_DELETE_` to shield `.txt` files.
* **Execution Engine**: `src/whisper-asr-service-docker.ps1` is the self-contained execution engine handling single files, configuration layering, container lifecycle, FFmpeg DSP, WhisperX ASR, and LLM summarization.

## ⚙️ Configuration Layering & Deterministic Lifecycle
* **No Guessing**: Never write heuristic fallback guessing loops for container names or ports.
* **Layered Config**: Base defaults live in `config/config.default.json` (tracked in Git); machine overrides live in `config/config.local.json` (gitignored). `Get-PipelineConfig` deep-merges them so partial overrides never erase baseline settings.
* **Deterministic Restarts**: Container lifecycle (`Ensure-WhisperContainerRunning`, `Restart-WhisperContainer`) strictly uses `$AppConfig.whisper_service.docker_container_name` and polls `/docs` or `/health` for readiness.

## 📊 Runtime Telemetry & Container Metadata Auditing
* **Explicit Version Logging**: Maintain split `"script_name"` and `"script_version"` (`v07.04`) in all `.log` outputs; never revert to unversioned filename fallback.
* **Resilient Container Metadata**: `Get-WhisperContainerMetadata` must forward `$PipelineConfig` and use multi-tier inspection (Docker inspect $\to$ candidate scan fallback $\to$ HTTP `/openapi.json`) to guarantee zero-null telemetry logs.
* **Silence & Zero-Speech Pipeline Invariants**: Empty segment responses from WhisperX (`segments.Count -eq 0`) must never abort script execution. Generate valid blank transcripts to avoid infinite retry loops in batch directory scans (ADR 0013).
* **Untagged Filename Warnings**: Maintain high-visibility red warnings (`-ForegroundColor Red`) whenever a media file lacks profile tagging or explicit CLI parameters.
* **Anti-Hallucination ASR Decoding**: Maintain `"condition_on_previous_text": false` on `meeting` profiles and low SNR audio. Autoregressive prompt-conditioning must not be used on silence or muted recordings to prevent infinite `"Thank you"` / `"Thanks for watching"` cascades. Enforce active speech duration floor in Stage 0 VAD and prune unaligned phantom tokens upon forced alignment backtrack failures (ADR 0017).

## 📁 Filesystem & Special Character Invariants
* **Strict `-LiteralPath` Standard**: Always use `-LiteralPath` on all file provider cmdlets (`Test-Path`, `Get-Content`, `Move-Item`, `Get-Item`, `Remove-Item`) so brackets `[ ]` and capture tags in media filenames (e.g. `[DQ] [PD] Meet...`) are never mishandled as PowerShell wildcard patterns (ADR 0012).
* **Curl Multipart Escaping & Forward Slash UNC Normalization**: Always enclose file paths in escaped double-quotes within curl arguments (`-F "audio_file=@`"$curlUploadFile`""`) AND normalize Windows backslashes to forward slashes (`$curlUploadFile = $TempProcessedFile -replace '\\', '/'`). This prevents multi-file delimiter splitting on commas and eliminates Windows `curl.exe` argument unescaping corruptions where `@"\\` collapses into invalid UNC roots (`\server\share`), both of which trigger `curl: (26) Failed to open/read local data from file`.
* **Universal Path Separators**: Use `Join-Path` instead of manual string concatenation with backslashes so paths evaluate correctly on both Windows and Unix filesystems.

## 🍏 Cross-Platform macOS Apple Silicon Invariants
* **Dual-Platform Architecture**: Supports Windows 11 (CUDA Docker) and macOS Apple Silicon (M1/M2/M3/M4 via `macos/whisperx_mlx_server.py`).
* **Platform-Agnostic Binaries**: Resolve binaries via `Get-PlatformBinaryName` (`ffmpeg.exe`/`curl.exe` on Windows, `ffmpeg`/`curl` on macOS).
* **Native MLX Lifecycle (`native-mlx`)**: When `docker_container_name` is `"native-mlx"`, the engine bypasses Docker CLI commands, obtains metadata from `/openapi.json`, and flushes Unified Memory via `POST /gc`.
* **PyTorch 2.6+ Compatibility**: In Python services, register safe globals for OmegaConf and force `weights_only=False` on trusted checkpoints to prevent unpickling crashes in Silero VAD and PyAnnote Diarization.
* **Hugging Face Classic Read Token Requirement**: PyAnnote 3.1 dynamically downloads sub-dependencies (`pyannote/wespeaker-voxceleb-resnet34-LM`). Narrow fine-grained tokens fail; require a **Classic Read Token** in `macos/.env` and accepted terms on both `pyannote/speaker-diarization-3.1` and `pyannote/segmentation-3.0`.

## 🔊 Audio Preprocessing & FFmpeg Demuxer Resilience
* **Video Stream Bypass (`-vn`)**: Always specify `-vn` prior to audio filter processing in execution engine commands. Video streams in high-resolution recordings (1080p, 1440p/2K, 4K) must never be demuxed or decoded into RAM during audio extraction.
* **Corrupted Packet & Cutfile Demuxer Tolerance**: Prepend `-err_detect ignore_err -fflags +genpts+igndts+discardcorrupt` to input arguments (`-i`). This prevents fatal demuxer abortions and 90+ second EOF freezing on truncated cutfile media (`.cutfile.`) or external storage read timeouts (`/Volumes/...`).
* **Audio Profile & Normalization Invariants**: Audio DSP filters (`dynaudnorm`, `speechnorm`, `loudnorm`) and MP3 compression (`libmp3lame`) execute exclusively on a single CPU core (GPU utilization is expected to be 0%). Never strip loudness normalization (`-16 LUFS`, `TP=-1.5`) or profile filter chains to gain raw conversion speed; acoustic normalization is essential for ASR transcription stability and PyAnnote diarization accuracy (ADR 0016).

## 🛡️ Public Release, Governance & Dual-Licensing Invariants
* **Public Identity & Neutralized Mocks**: Canonical project is **`whisper-llm-notes`**. All test fixtures and docstrings must use generic mock paths (`\\server\share\...` or `C:\Users\test,user\...`). Never commit proprietary hostnames or private directories.
* **Dual-Licensing Governance (GNU AGPL-3.0 + Commercial)**: Published under GNU AGPL-3.0 with commercial licensing rights exclusively retained by DataQuo (ADR 0018). Contributed changes must remain compatible with DataQuo's dual-licensing rights.
* **macOS Dependency Tracking**: `.gitignore` must maintain the negative pattern `!macos/requirements*.txt` so public clones include automated setup requirements.



