# ADR 0008: Reverberant Acoustic Profiles, ASR Decoding Tuning, Language Guards & LLM Reconstruction

## Status
Accepted (v06.01)

## Context
When processing CCTV surveillance and IP camera recordings (such as Hikvision / HiLook `IPC-T280HA-LUF-SL` mounted in tiled corridors and concrete hallways), standard transcription pipelines experienced severe accuracy degradation:
1. **Acoustic Bottlenecks**: Default IP camera audio compression (`G.711u`, 8 kHz sampling rate, 64 kbps) cuts off frequencies above 3.7 kHz, completely discarding human sibilants and fricatives (*s, š, c, č, z, ž, f, t, d* in 4–8 kHz).
2. **Reverberation & Late Reflections (RT60 ~ 1.5–2.5s)**: Multi-path sound reflections from concrete walls arrived with high acoustic pressure, smearing formant boundaries.
3. **Fine-Tuned Model Hallucinations**: Testing Slovak-specialized models (`kinit/whisper-large-v3-sk`) revealed heavy parliamentary language model bias (*"pán poslanec", "záverečný zákon"*), as the model's language prior overrode ambiguous acoustic inputs.
4. **Turbo Model Repetition Loops**: Testing lightweight Turbo models resulted in infinite phrase loops (*"na päťkrát položený..."*) due to shallow depth.
5. **CPU Dereverberation Bottlenecks**: Attempting CPU-based statistical dereverberation (WPE via `nara_wpe`) locked up the CPU at 100% and caused memory exhaustion due to uncompiled $O(N^3)$ matrix inversion across 25,000 frames.

## Decision
1. **Dedicated Reverberant Profiles (`hallway` & `echoed`)**:
   - **`hallway` (Tag: `H`)**: Fine-tuned Slovak model (`whisper-large-v3-kinit-sk-ct2`) with `vad_onset=0.55`, `vad_offset=0.45`, `temperature=0.0`.
   - **`echoed` (Tag: `E`)**: Multilingual OpenAI `large-v3` with greedy decoding (`beam_size=1`), `condition_on_previous_text=false`, `repetition_penalty=1.2`, `no_repeat_ngram_size=3`.
   - **Standardized Filter Chain (`HALLWAY-NORM_HP-LP-DN-EQ` & `ECHOED-NORM_HP-LP-DN-EQ`)**:
     - `HP` (High-Pass 220 Hz): Eliminates low-frequency structural rumble and HVAC thumps.
     - `LP` (Low-Pass 3700 Hz): Removes high-frequency aliasing and sensor noise.
     - `DN` (FFT Spectral Denoise `afftdn` -14 dB): Attenuates stationary air noise without destroying speech transients.
     - `EQ` (Resonant Notch Equalizer 380 Hz, Q=1.2, -4 dB): Suppresses the resonant boxy frequency mode of concrete hallways.
     - `NORM` (EBU R128 Loudness Normalization -16 LUFS, TP -1.5): Standardizes broadcast speech levels.
2. **Tuned ASR Decoding Parameters**:
   - Explicitly passing `beam_size=1` (greedy search) stops Whisper from exploring and generating hallucinated multi-sentence completions.
   - `condition_on_previous_text=false` prevents hallucinated phrases in one segment from corrupting subsequent timestamps.
   - `repetition_penalty=1.2` and `no_repeat_ngram_size=3` physically eliminate repeating loop artifacts.
3. **Language-Aware Model Guard**:
   - In `whisper-asr-service-docker.ps1`, if a language-specific model (such as `kinit-sk`) is configured for a profile, it is strictly dispatched ONLY when `Language == 'sk'`.
   - For Czech (`cs`) and English (`en`), the engine automatically falls back to baseline multilingual `large-v3`, preventing catastrophic cross-lingual misinterpretations.
4. **Context-Aware LLM Post-Reconstruction**:
   - Added specialized acoustic prompt instructions into LM Studio (`.NOTES.md`) and Ollama (`.SUMMARY.md`) templates when processing `hallway` or `echoed` profiles.
   - The LLM is instructed to reconstruct phonetic misinterpretations and grammatical agreement in the target language (SK/CS/EN) while strictly preserving genuine conversational context.
5. **Selective LLM Execution Switches**:
   - Added `-OnlyOllama` (aliases: `-OnlyOlama`, `-OllamaOnly`) to generate exclusively `.SUMMARY.md` via Ollama.
   - Added `-OnlyLMStudio` (aliases: `-LMStudioOnly`, `-OnlyLM`) to generate exclusively `.NOTES.md` via LM Studio.
6. **Camera Hardware Optimization Guidelines**:
   - Documented recommended camera hardware settings: switch audio encoding from default `G.711u` (8 kHz) to `AAC` (16 kHz, 64–128 kbps), enable hardware `Environmental Noise Filtering`, and reduce microphone input volume to 60–70% to prevent acoustic clipping.

## Consequences
### Positive
* **Conversational Accuracy**: Hallucinations of parliamentary speech eliminated; output reflects natural colloquial dialogue.
* **GPU Speed & Stability**: GPU-accelerated WhisperX execution on NVIDIA RTX 3050 completes in seconds with 0% CPU lockup.
* **Multi-lingual Safety**: Slovak fine-tuned models cannot corrupt Czech or English transcriptions.
* **Flexible Orchestration**: Users can selectively trigger Ollama, LM Studio, or pure WhisperX via CLI flags.

### Negative
* True acoustic reconstruction of 8 kHz G.711u remains bounded by Shannon channel capacity; full phonetic fidelity requires setting the IP camera to 16 kHz AAC.
