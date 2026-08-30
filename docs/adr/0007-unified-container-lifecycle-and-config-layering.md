# ADR 0007: Unified Container Lifecycle Management, Configuration Layering & Orchestrator Decoupling

## Status
Accepted (v06.00)

## Context
As the WHISPER pipeline evolved to support batch transcription, multi-speaker diarization, and dual-LLM summarization on constrained developer hardware (NVIDIA RTX 3050 Laptop GPU, 4 GB VRAM), several operational issues emerged:
1. **Container Restarts & Guessing Heuristics**: Ad-hoc container restarting failed when Docker container names differed between developer setups (`whisperx-api`) and standard deployments (`whisper-asr-service`). Runtime guessing created non-deterministic behavior.
2. **Configuration Conflicts**: Changing tracked base configuration (`config.default.json`) dirtying git status or causing merge conflicts across machines.
3. **Orchestrator Code Bloat**: `_MASTER_WHISPER.ps1` accumulated duplicate configuration loaders and container management logic that belonged in the execution engine.
4. **PowerShell 7 Remoting Freezes**: Deprecated `Get-WmiObject` calls stalled execution for ~57 seconds while PowerShell Core spawned Windows PowerShell 5.1 remoting modules.
5. **Multi-Channel & Silent Video Edge Cases**: Multi-channel AAC audio (e.g. 7.1 layout) and silent recordings generated 0-byte or corrupt MP3 headers (425 bytes), crashing downstream WhisperX API calls.

## Decision
1. **Single Source of Truth in `src/`**:
   - `src/_MASTER_WHISPER.ps1` and `src/whisper-asr-service-docker.ps1` are the sole authoritative scripts. Root script duplicates have been removed.
2. **Clean Architectural Decoupling**:
   - **`_MASTER_WHISPER.ps1` (Pure Batch Orchestrator)**: Focuses exclusively on folder scanning, filename parameter parsing (`.LL-X#`), detecting missing outputs (`.json`, `.txt`, `.srt`, `.md`), and invoking the engine.
   - **`whisper-asr-service-docker.ps1` (Self-Contained Execution Engine)**: Manages configuration layering, Docker container pre-flight and restart lifecycles, FFmpeg DSP audio normalization, WhisperX API interaction, and LLM summarization.
3. **Deep Configuration Layering (`Get-PipelineConfig`)**:
   - Base defaults are loaded from `config/config.default.json` (tracked in Git).
   - Local machine overrides from `config/config.local.json` (gitignored) are deep-merged on top, preserving base defaults while allowing selective local overrides.
4. **Deterministic Container Lifecycle (`Ensure-WhisperContainerRunning` & `Restart-WhisperContainer`)**:
   - Strictly executes the configured `docker_container_name` without guessing.
   - Pre-flight checks start stopped containers and poll `/docs` or `/health` until ready.
   - Post-transcription and GPU OOM recovery flushes VRAM by restarting the container and verifying API readiness.
5. **Multi-Channel Downmix (`-ac 1`) & Corrupt File Validation**:
   - Added `-ac 1` mono downmixing across all DSP filter chains (`phone`, `meeting`, `distant`).
   - Validates that intermediate audio is `Length > 1024` bytes; empty audio streams are cleanly caught and reported.
6. **Native CIM Performance**:
   - Replaced `Get-WmiObject` with `Get-CimInstance` in `Get-SystemInfo`, eliminating the 57-second remoting delay.
7. **`-DisableLLMs` Switch**:
   - Added `[switch]$DisableLLM` (aliases: `DisableLLMs`, `SkipLLM`, `NoLLM`) to run pure WhisperX transcription without Ollama or LM Studio.

## Consequences
### Positive
* **Deterministic & Robust**: Zero container guessing; explicit configuration guarantees predictable restarts across all developer and production machines.
* **Maintainable Codebase**: `_MASTER_WHISPER.ps1` reduced from ~480 lines to ~220 lines.
* **Fast & Responsive**: Immediate GPU detection with 0s latency overhead.
* **VRAM Safety**: Clean container restart guarantees 0.0 GB VRAM consumption between files, preventing CUDA OOM on 4 GB GPUs.
* **Edge-case Resilient**: Handles 5.1/7.1 audio tracks and zero-audio screen recordings gracefully.

### Negative
* Local machines with non-default container names must maintain a `config/config.local.json` file.