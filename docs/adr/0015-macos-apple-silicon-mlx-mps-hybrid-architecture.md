# ADR 0015: macOS Apple Silicon (M2 Max) Native MLX + PyTorch MPS Hybrid Acceleration & 32 GB Unified Memory Management

## Status
Accepted (v07.00)

## Context
The WHISPER pipeline has historically operated on Windows 11 with NVIDIA CUDA acceleration via Docker (managed by Portainer). To offload processing onto a developer workstation (MacBook Pro M2 Max, 12-core CPU, 30/38-core GPU, 16-core Apple Neural Engine, 32 GB Unified Memory with 400 GB/s bandwidth), the pipeline requires full GPU hardware acceleration on macOS.

Several critical platform constraints and hardware realities were evaluated:

### 1. The Container GPU Boundary on Apple Silicon
On macOS, Docker containers (whether hosted via OrbStack or Docker Desktop) execute inside an isolated Linux ARM64 virtual machine. Apple does not provide Linux kernel drivers for Metal Performance Shaders (MPS). Consequently, any WhisperX container run inside Docker/OrbStack is restricted to unaccelerated Linux CPU execution, resulting in an 8x–15x performance degradation.

### 2. Dual-Engine Heterogeneity in WhisperX
WhisperX relies on three distinct computational stages:
1. **ASR Transcription (`large-v3`, `kinit-sk`)**: ~80% of total compute. Powered by `CTranslate2` (`faster-whisper`) on CUDA. On macOS, CTranslate2 does not support Apple Metal GPU and is restricted to CPU.
2. **Word-Level Forced Alignment (`wav2vec2`)**: ~5% of compute. Powered by PyTorch, which natively supports Apple Metal GPU via `device="mps"`.
3. **Speaker Diarization (`pyannote.audio 3.1`)**: ~15% of compute. Powered by PyTorch with native `mps` support.

### 3. Unified Memory Pressure in a 32 GB Multi-Model Workflow
The M2 Max shares 32 GB of RAM across system processes, Whisper models (~5.5 GB), LM Studio LLMs (e.g. `qwen3.6-35b-a3b` at 4-bit, ~21 GB), and Ollama (`gemma3:4b`, ~3.3 GB). Retaining Whisper models permanently resident in VRAM forces macOS into disk swap when LM Studio processes detailed notes (`.NOTES.md`), reducing throughput by up to 70%.

---

## Decision & Evaluation of Alternatives

### Alternative 1: Containerized Execution in OrbStack (Linux ARM64 CPU)
- *Mechanism*: Run the existing Docker container inside OrbStack with `compute_type=int8` on CPU.
- *Verdict*: **Rejected**. CPU-only transcription takes 15–25 minutes for a 1-hour recording, completely defeating the purpose of offloading to the M2 Max GPU.

### Alternative 2: whisper.cpp / whisper-server (CoreML + Metal)
- *Mechanism*: Use `whisper.cpp` with CoreML encoder acceleration on the 16-core Apple Neural Engine.
- *Verdict*: **Rejected**. Lacks `wav2vec2` phoneme alignment, lacks `pyannote.audio 3.1` speaker diarization, and cannot enforce exact `min_speakers`/`max_speakers` constraints from filename tags.

### Alternative 3: mlx-audio Server (Sortformer Diarization)
- *Mechanism*: Use `mlx-audio` with NVIDIA Sortformer diarization.
- *Verdict*: **Rejected**. Hardcoded to a 4-speaker maximum, lacks `wav2vec2` forced alignment (causing timestamp drift and speaker boundary misattribution), and breaks API parity with WhisperX.

### Selected Strategy: Hybrid Native FastAPI Server (MLX-Whisper + PyTorch MPS WhisperX)

1. **Stage 1 (ASR on M2 Max Metal GPU via Apple `mlx-whisper`)**:
   - Transcribes speech in FP16 on the 30/38-core M2 Max GPU at ~400 GB/s bandwidth.
   - Transparently routes baseline requests (`large-v3`) to `mlx-community/whisper-large-v3-mlx` (auto-detecting LM Studio's local model cache if present).
   - Routes Slovak requests (`kinit-sk`) to converted local MLX FP16 weights (`~/.cache/whisper-mlx/whisper-large-v3-kinit-sk-mlx`).

2. **Stage 2 & 3 (Alignment & Diarization on M2 Max PyTorch `mps` GPU)**:
   - Executes `whisperx.load_align_model` (`wav2vec2` for `sk`, `cs`, `en`) on `mps`.
   - Executes `whisperx.DiarizationPipeline` (`pyannote/speaker-diarization-3.1`) on `mps`, enforcing exact `min_speakers` and `max_speakers` bounds from `.LL-X#` filename conventions.

3. **Stage 4 (Stateless Unified Memory Lifecycle & Fast GC)**:
   - Automatically unloads model references and calls `mx.metal.clear_cache()` and `torch.mps.empty_cache()` at the completion of each `/asr` request (<0.1s).
   - Exposes `POST /gc` endpoint for orchestrator-driven memory clearing.

4. **100% Cross-Platform PowerShell Script Compatibility**:
   - `src/whisper-asr-service-docker.ps1` and `src/_MASTER_WHISPER.ps1` run unmodified on Windows 11 and macOS PowerShell 7 (`pwsh`), using `Test-IsWindowsPlatform`, `Get-PlatformBinaryName`, and `Join-Path`.

5. **Edge Cases Resolved in Live Verification**:
   - **PyTorch 2.6 `weights_only=True` Unpickling**: PyTorch 2.6 changed `torch.load` default to `weights_only=True`, breaking Silero VAD and PyAnnote model unpickling (`omegaconf.listconfig.ListConfig`). Resolved via `torch.serialization.add_safe_globals([ListConfig, DictConfig])` and defaulting `weights_only=False` on trusted model checkpoints.
   - **Gated PyAnnote 3.1 Authentication**: Requires accepting user conditions on both `pyannote/speaker-diarization-3.1` AND `pyannote/segmentation-3.0` on Hugging Face, plus configuring a Fine-Grained token with gated repository read permissions.
   - **Curl Multipart Quoting for Filenames with Commas**: Curl parses `,` as a delimiter for multiple files unless enclosed in quotes. Updated PowerShell invocation to `-F "audio_file=@`"$TempProcessedFile`""` to prevent `curl: (26) Failed to open/read local data from file`.
   - **SpeechBrain Traceback Formatting**: Patched `speechbrain.utils.importutils.LazyModule.__getattr__` to prevent traceback inspection crashes when optional external modules (like `k2`) are omitted.

---

## Consequences
### Positive
* **100% Native GPU Utilization**: Full M2 Max Metal and MPS acceleration across transcription, alignment, and diarization.
* **Exceptional Throughput**: Live verification achieved Real-Time Factors of `0.191x` to `0.608x` (transcribing speech 5.2x faster than real-time) with 14W–45W Metal GPU engagement.
* **Zero Quality Compromise**: Preserves PyAnnote VAD pre-segmentation, `wav2vec2` phoneme alignment, and PyAnnote 3.1 diarization parity with Windows NVIDIA results.
* **No Memory Swap**: 32 GB Unified Memory is cleanly reclaimed (<0.1s via `POST /gc`) before LM Studio and Ollama inference begins.
* **Unified Codebase**: Single cross-platform script set (`src/`) for both Windows 11 and macOS workstations.

### Negative
* First-time setup on macOS requires running `macos/setup_macos.sh` to configure the Python virtual environment and download model weights.
* Hugging Face account must have agreed to gated license conditions for PyAnnote models.
