# ADR 0010: Telephone Audio Diarization, Receptive Boundary Priming & Forced Alignment Synchronization

## Status
Accepted (v06.03)

## Context
During batch transcription of conversational telephone recordings using the `phone` profile (`.LL-P#` naming convention), significant speaker diarization anomalies were observed on real-world dual-speaker calls (e.g. `call 01.CS-P2.m4a`):
1. **Unassigned Opening Utterances**: The first 2–3 conversational turns (0.0s to 6.0s: *"Zubík Štefán"*, *"Ano, prosím"*, *"Zubík, Loudauto"*) had no speaker assigned (`speaker: null` / `[NONE]`).
2. **Speaker Misattribution on Question/Answer Transitions**: Utterance 4 (*"Pane Michalíku, budeme odstraňovat teda tu diagnostiku a ten naftový filtr k tomu?"*) was spoken by the service advisor (Zubík), but was labeled as the customer (Michalík / `SPEAKER_00`), incorrectly merging both speaker turns under one speaker label.
3. **Diacritic Corruption on Clean-up**: Accented Czech and Slovak characters (`ě, š, č, ř, ž, ý, á, í, é, ň`) were intermittently stripped during text repetition deduplication.

---

## Technical Root Cause Analysis

A deep architectural trace across the 3-stage WhisperX pipeline (Whisper ASR -> Wav2Vec2 Forced Alignment -> PyAnnote Diarization -> Word Speaker Assignment) revealed three distinct mechanisms causing these failures:

### 1. PyAnnote Convolutional Sliding Receptive Field (Left-Edge Defect)
PyAnnote's neural network operates on a temporal sliding window (~5–10 seconds of acoustic context). When an audio file begins with immediate speech at `0.0s`, the convolutional filters have no preceding audio context (left-edge boundary defect). For short, isolated greetings, embedding confidence thresholds are not met, resulting in unassigned speaker clusters until ~12.5s to 14.0s into the call.

### 2. Wav2Vec2 Forced Alignment Silence Token Absence (The Primary Attribution Culprit)
Wav2Vec2 aligns phonemes to the audio waveform without an internal voice activity detection (VAD) or silence token. When a speaker completes an utterance followed by a conversational pause (e.g. Zubík finishes speaking at `10.4s` and Michalík pauses until `14.1s`), Wav2Vec2 stretches the final phoneme/word (`"tomu?"`) across the entire 3.7 seconds of silence until `14.12s`.

### 3. Overlap-Based Speaker Attribution (`assign_word_speakers`)
WhisperX maps word timestamps to PyAnnote speaker intervals based on temporal overlap:
* Because `"tomu?"` was artificially stretched to `14.12s`, it overlapped with Michalík's PyAnnote cluster starting at `14.14s` (`SPEAKER_01`).
* Because words 1 through 9 (*"Pane"*, *"Michalíku"*, *"budeme"*, etc.) had `speaker: null` due to the left-edge boundary defect, the *only* word in the entire segment with a speaker label was `"tomu?"` (`SPEAKER_01`).
* WhisperX's segment aggregation assigns the segment to the dominant speaker among labeled words, misattributing Zubík's entire question to Michalík.

### 4. Encoding Bug in Regex Cleaner
`Clean-TranscriptText` contained literal em-dashes `[–—]` in its regex patterns. Under non-BOM text streams, these literals resolved as Windows-1252 byte artifacts, stripping diacritics.

---

## Decision & Evaluation of Alternatives

We evaluated four potential solutions:

### Option A: Post-Hoc Speaker Heuristics / Backfilling in PowerShell [REJECTED]
* **Mechanism**: Write script-level rules in `src/whisper-asr-service-docker.ps1` to backfill `speaker: null` by looking ahead or alternating speaker labels.
* **Why Rejected**: Explicitly rejected per core project principles: *"A script should not be fixing what Whisper messes up. Whisper should handle correct diarization."* Heuristic backfilling is fragile, fails on multi-turn monologues, and risks cascading speaker inversion throughout the entire document.

### Option B: Prepend 1.5s Lead-in Silence in FFmpeg + In-Memory Timestamp Compensation [ADOPTED AS CONFIGURABLE PROFILE FEATURE]
* **Mechanism**:
  1. Add `"lead_in_silence_seconds": 1.5` to `config/config.default.json`.
  2. Prepend `adelay=1500:all=1` in FFmpeg audio preprocessing before upload to WhisperX.
  3. Implement `Adjust-TranscriptTimestamps` in `src/whisper-asr-service-docker.ps1` to subtract the 1.5s offset from all segment, word, and word-segment timestamps (clamped to `0.0s`, rounded to 3 decimals) before outputting `.json`, `.txt`, `.srt`, `.vtt`, and `.tsv`.
* **Pros**: Primes PyAnnote's receptive field; sub-second timestamp compensation guarantees zero drift against original media files; completely transparent across all 5 generated formats.
* **Empirical Verification Finding**: While timestamp compensation operates flawlessly, artificial lead-in silence can shift Whisper ASR's initial 30-second attention window on certain quiet recordings, causing Whisper's autoregressive decoder to skip short opening words. Retained as a first-class profile configuration option (`lead_in_silence_seconds`) so users can enable or tune it per acoustic profile.

### Option C: Forced Alignment Duration Clamping / VAD Trimming [CONTAINER ARCHITECTURE]
* **Mechanism**: Cap maximum word duration (e.g. clamp word duration > 1.2s to `start + 0.4s` or apply energy VAD) *before* `assign_word_speakers` executes.
* **Analysis**: This addresses the root cause of silence-stretching. However, because `assign_word_speakers` executes inside Python inside the Docker container (`learnedmachine/whisperx-asr-service`), implementing Option C requires building and maintaining a custom Docker image.

### Option D: Audio Bandwidth Calibration (Wideband vs. Telephony Narrowband) [ADOPTED]
* **Mechanism**: Re-evaluated frequency response for the `phone` profile.
* **Decision**: While wideband (`80–7500 Hz`) provides richer audio, it overlaps almost entirely with the `meeting` profile (`80–8000 Hz`). To preserve specialized acoustic separation for band-limited telephone calls, the `phone` profile was finalized with:
  ```text
  highpass=f=200,lowpass=f=3500,speechnorm=e=4:r=0.0001:l=1,loudnorm=I=-16:TP=-1.5:LRA=11
  ```
  This sharp bandpass cuts out low-frequency rumble and high-frequency cellular artifacts, while smoothed `speechnorm` levels disparate caller volumes.

---

## Implementation Details (v06.03)

1. **`lead_in_silence_seconds` in `config/config.default.json`**:
   Configurable per-profile parameter (`1.5s` for `phone`, `0.0s` for others).
2. **Dynamic `adelay` Injection**:
   Prepended dynamically to FFmpeg filter chains in `src/whisper-asr-service-docker.ps1` when `lead_in_silence_seconds > 0`.
3. **`Adjust-TranscriptTimestamps` Helper**:
   Performs deep recursive offset subtraction on `$ApiResult.segments`, `$seg.words`, and `$ApiResult.word_segments`, clamping to `0.0s`.
4. **Diacritic & Encoding Hardening**:
   Updated `Clean-TranscriptText` to use `\u2013\u2014` unicode escapes and enforced UTF-8 without BOM (`[System.IO.File]::ReadAllText($Path, $Utf8NoBom)`).
5. **Comprehensive Automated Unit Testing**:
   Added Pester tests in `tests/whisper-asr-service-docker.Tests.ps1` verifying offset subtraction, zero-clamping, and configuration loading.

---

## Consequences

### Positive
* **Zero Timecode Drift**: Sub-second compensation ensures generated subtitles (`.srt`, `.vtt`) and spreadsheet timecodes (`.tsv`) align with millisecond precision to the original media.
* **Architectural Decoupling**: Orchestrator (`_MASTER_WHISPER.ps1`) remains clean; all audio DSP and compensation logic is encapsulated in the engine and configuration schema.
* **Full Diacritic Safety**: Czech and Slovak special characters are protected against regex-induced corruption.
* **Telemetry Transparency**: Transcription logs explicitly record `lead_in_silence_seconds` and container runtime metadata.

### Negative / Trade-offs
* Trailing word stretching on long pauses is an inherent limitation of Wav2Vec2 forced alignment that cannot be fully mitigated outside the Docker container image without post-hoc text heuristics.
