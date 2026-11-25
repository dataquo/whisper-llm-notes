# ADR 0017: Cross-Platform Video Transcoding, Anti-Hallucination ASR Decoding, and UNC Path Normalization

## Status
Accepted (v07.02)

## Context
During cross-platform deployment across Windows 11 (CUDA hardware, TrueNAS SMB network storage) and macOS Apple Silicon (M2 Max, Unified Memory), three distinct operational failure modes were observed:

1. **macOS Video Transcoding Failure on Apple Silicon (`-hwaccel cuda`)**:
   `src/_MASTER_WHISPER.ps1` hardcoded `-scene "special-quality-hw-dec-cuda"` when invoking the external video transcoding companion script (`convert_DJI_videos_with_MetaData.ps1`). Because Apple Silicon lacks Nvidia CUDA hardware, FFmpeg failed immediately with `Device creation failed: -12. No device available for decoder: device type cuda needed for codec h264. Hardware device setup failed for decoder: Cannot allocate memory`. The companion script already included a dedicated Apple Silicon hardware decoding scenario (`special-quality-hw-opt-Apple_M2` using `-hwaccel videotoolbox`), but the orchestrator did not select it dynamically based on the host OS.

2. **Runaway "Thank You" Hallucination Cascades on Silent Screen Recordings**:
   Screen recording media (captured via Microsoft Game DVR) often contains muted microphones, prolonged pauses, or ambient noise without dialogue. Under the `meeting` profile (`MEETING-NORM_HP-LW-DN`), FFmpeg's Dynamic Audio Normalizer (`dynaudnorm=f=150:g=15`) amplifies ambient noise floor up to broadcast loudness (-16 LUFS). When fed into OpenAI Whisper (`mlx-whisper` on macOS or `faster-whisper` on Windows):
   - Whisper's autoregressive decoder acts as a language model and hallucinates polite internet subtitle boilerplate (`" Thank you."`).
   - With `condition_on_previous_text=true` (Whisper's default), the hallucination from the first 30-second window is fed as the context prompt for the next window, locking the decoder into an infinite loop where every segment across the 11- to 19-minute recording outputs `" Thank you."`.
   - `whisperx.align` (wav2vec2) fails backtrack alignment on phantom tokens (`Failed to align segment: backtrack failed, resorting to original...`).
   - Downstream deduplication in `whisper-asr-service-docker.ps1` collapses all identical consecutive segments into a single 3-token line: `"Thank you"`.

3. **PyTorch 2.6+ `WeightsUnpickler` and Hugging Face Token Scope Failures**:
   On macOS, PyTorch 2.6 defaults `torch.load` to `weights_only=True`, which blocked `omegaconf.base.ContainerMetadata` when unpickling PyAnnote and Silero VAD checkpoints. Additionally, users configuring Hugging Face **Fine-grained Tokens** restricted to `pyannote/speaker-diarization-3.1` and `segmentation-3.0` failed to initialize diarization because the composite pipeline dynamically downloads an unlisted sub-dependency (`pyannote/wespeaker-voxceleb-resnet34-LM`), triggering `'NoneType' object has no attribute 'to'`.

4. **Windows Curl Exit Code 26 on UNC Network Storage (`\\truenas\...`)**:
   When processing media from network shares (TrueNAS SMB shares via `\\truenas\...`), `src/whisper-asr-service-docker.ps1` constructed curl multipart arguments as `-F "audio_file=@\"$TempProcessedFile\""`. On Windows, `curl.exe`'s argument unescaping parsed `@"\\` as an escaped quote sequence, collapsing the double backslash into a single backslash (`\truenas\...`), which Windows cannot resolve as a UNC root, triggering `curl: (26) Failed to open/read local data from file/application`.

---

## Decisions

### 1. Dynamic Platform-Aware DJI Video Conversion
`Invoke-DjiConversion` in `src/_MASTER_WHISPER.ps1` dynamically detects the host operating system:
* **macOS (`$IsMacOS`)**: Automatically invokes scene `special-quality-hw-opt-Apple_M2`, utilizing Apple VideoToolbox hardware decoding while maintaining software SVT-AV1 encoding.
* **Windows (`$IsWindows`)**: Automatically invokes scene `special-quality-hw-dec-cuda`, utilizing Nvidia CUDA hardware decoding.
* **CLI Override**: Added explicit parameter `-DjiScene` (alias `-DjiProfile`) to allow manual scenario selection (`day`, `night`, etc.) across all platforms.

### 2. Multi-Tier Anti-Hallucination ASR Decoding
To prevent silence and low-energy noise from locking Whisper into hallucination cascades:
* **Baseline Decoder Disconnection**: Added `"condition_on_previous_text": false` to the `meeting` profile in `config/config.default.json` and enforced it as the default in `macos/whisperx_mlx_server.py`. Each 30-second window is decoded strictly from acoustic signals without prompt-contamination from previous segments.
* **Silence Thresholding**: Passed `hallucination_silence_threshold=2.0` and `no_speech_threshold=0.6` to `mlx_whisper.transcribe`.
* **VAD Speech Floor**: Added an active speech duration floor in Stage 0 VAD (`total_speech >= 0.5s`). Recordings devoid of voice activity immediately return zero segments.
* **Phonetic Alignment Pruning**: Prunes known phantom utterances (`"Thank you"`, `"Thanks for watching"`) when wav2vec2 forced alignment fails (`backtrack failed` / no aligned word phonemes) or `no_speech_prob > 0.4`. If all segments are phantom tokens, the response returns empty segments, triggering the Zero-Speech Invariant ([ADR 0013](0013-empty-speech-vad-silence-and-untagged-profile-alerts.md)) to generate valid blank transcripts cleanly.

### 3. Forward Slash Normalization for Curl UNC Network Paths
In `src/whisper-asr-service-docker.ps1`, file paths are normalized to forward slashes (`$curlUploadFile = $TempProcessedFile -replace '\\', '/'`) prior to constructing curl multipart arguments:
* Windows Win32 APIs and `curl.exe` natively accept forward slashes for UNC shares (`//truenas/_DOWNLOADS/...`).
* Eliminates backslash escape collisions (`@"\\` $\to$ `\`) in `curl.exe` while preserving literal path quotation around spaces, commas, and square brackets `[ ]`.

### 4. Canonical macOS Configuration & Real-Time Token Diagnostics
* **Canonical Path**: Standardized on `/Users/<user>/MEGA/_SCRIPTS/WHISPER/macos/.env` as the primary configuration file for the native MLX service, with fallback to repository root `.env`.
* **PyTorch 2.6 Compatibility**: Enforced `kwargs["weights_only"] = False` on trusted checkpoints and allowlisted all OmegaConf metadata classes (`ContainerMetadata`, `Node`, `Metadata`, `ListConfig`, `DictConfig`, and primitive nodes).
* **Startup Hub Verification**: Added proactive Hugging Face API validation in `macos/whisperx_mlx_server.py` lifespan startup, testing authentication and model accessibility for both `pyannote/speaker-diarization-3.1` and `pyannote/segmentation-3.0` with clear diagnostic alerts.

---

## Consequences & Trade-offs

### Pros
* **Zero Platform Transcoding Crashes**: Video pre-processing offloads to hardware decoding on both Apple Silicon (VideoToolbox) and Windows (CUDA) without user intervention.
* **Elimination of "Thank You" Loops**: Meetings with silent gaps, muted screen captures, or background hum transcribe cleanly without runaway repetitive loops or corrupted AI summaries.
* **Seamless Network Share Ingestion**: TrueNAS and SMB network paths transcribe directly on Windows without copying files to local drive letters first.
* **Instant Diagnostic Feedback**: Missing Hugging Face tokens or unaccepted gated model agreements are highlighted in the server banner before processing starts.

### Cons & Mitigations
* *Potential Word Boundary Truncation with `condition_on_previous_text=false`*: Disabling previous text conditioning can occasionally lose context for words cut directly across a 30-second window.  
  *Mitigation*: WhisperX forced alignment (`whisperx.align`) reconstructs exact sub-second word boundaries independently, eliminating boundary clipping.
* *Classic vs. Fine-Grained Token Policy*: Hugging Face Fine-Grained tokens require manually allowlisting sub-dependencies (`pyannote/wespeaker-voxceleb-resnet34-LM`).  
  *Mitigation*: Proactive startup diagnostics identify denied models immediately; documentation recommends Classic Read tokens.
