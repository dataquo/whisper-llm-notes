# ADR 0013: Empty Speech Handling, VAD Silence Guard, and Visual Untagged Profile Alerts

## Status
Accepted (v06.05)

## Context
When ingesting arbitrary audio recordings through the batch orchestrator (`src/_MASTER_WHISPER.ps1`), media files frequently arrive without standard filename tagging conventions (e.g. `Sample 2026-07-07 14-21-24-C01.mp4`). In these scenarios, two interconnected failure modes surfaced:

1. **Silent Fallback to Default Profile**:
   The orchestrator and execution engine silently fell back to the default `phone` DSP profile (`200–3500 Hz` bandpass filtering, 1.5s lead-in silence priming, `vad_filter = false`) without giving the user clear, high-priority visual feedback in the terminal that profile parameters should be specified.

2. **WhisperX Internal Server Error on No-Speech / Low-Volume Audio (`IndexError: list index out of range`)**:
   Under certain audio profiles (especially `phone` with low-volume, reverberant, or silent capture files), PyAnnote Voice Activity Detection (VAD) detects 0 active speech segments (`len(vad_segments) == 0`).
   In the upstream WhisperX inference engine (`whisperx/asr.py` within the `learnedmachine/whisperx-asr-service` container), the transcribe pipeline yielded an empty generator:
   ```python
   for idx, out in enumerate(self.__call__(data(audio, vad_segments), batch_size=batch_size, num_workers=num_workers)):
   ```
   Hugging Face Transformers `Pipeline.__call__` attempted to evaluate `if is_valid_message(inputs[0]):`, throwing an unhandled `IndexError: list index out of range`, aborting HTTP request processing with HTTP 500.

3. **PowerShell Engine Aborting on Zero Segments**:
   Even if the API returned an empty segment payload (`{"text":[],"language":"en","segments":[],"word_segments":[]}`), the PowerShell engine in `src/whisper-asr-service-docker.ps1` evaluated:
   ```powershell
   if (-not $ApiResult.segments) { 
       Write-Error "Transcription returned no segments.`nResponse: $($Response | ConvertTo-Json)"
       exit 1
   }
   ```
   Because PowerShell evaluates an empty array `@()` as falsy (`-not @() -> $true`), the script terminated with a fatal exit code, preventing generation of secondary formats (`.txt`, `.srt`, `.vtt`, `.tsv`, `.NOTES.md`, `.SUMMARY.md`) and stalling directory batch execution.

---

## Decision & Evaluation of Alternatives

### Alternative 1: Disable PyAnnote VAD on All Untagged Audio
* *Mechanism*: Automatically turn off VAD whenever no profile tag is defined.
* *Pros*: Avoids PyAnnote VAD returning 0 segments.
* *Cons*:
  * Causes massive hallucination loops in Whisper on long silent recordings or muffled background audio.
  * Conflicts with ADR 0008 (greedy reverberation decoding) and ADR 0010 (lead-in silence priming).
* *Verdict*: **Rejected**.

### Alternative 2: Discard Empty Files and Halt Batch Processing
* *Mechanism*: Treat 0 detected segments as a hard user error and delete preprocessed files.
* *Pros*: Saves downstream LLM summarization tokens.
* *Cons*:
  * Breaks batch automation: the orchestrator would continuously re-attempt to transcribe the same non-speech recording on subsequent folder scans.
  * User receives no transcript or notes acknowledging that the recording had no audible speech.
* *Verdict*: **Rejected**.

### Selected Strategy: Multi-Tiered Silence Resilience & Visual Profile Alerts (Accepted)

1. **High-Visibility Terminal Warning for Untagged Profiles**:
   - In both `src/_MASTER_WHISPER.ps1` and `src/whisper-asr-service-docker.ps1`, untagged media files emit a prominent red warning:
     ```text
     WARNING: No profile tag defined in filename '<filename>'. Using default profile 'phone' with auto-detection. Recommended: tag filename as [name].[LL]-[X][#].[ext] (e.g. .SK-M2, .CS-P2, .EN-D1).
     ```
   - Uses `-ForegroundColor Red` in `Write-Host` to guarantee immediate visibility against yellow processing status headers.

2. **WhisperX Upstream Empty Segment Guard (`whisperx/asr.py`)**:
   - Patched and committed into the Docker container image (`learnedmachine/whisperx-asr-service:latest`):
     ```python
     if len(vad_segments) == 0:
         return {'segments': [], 'language': language}
     ```
   - Prevents calling Transformers pipeline iterator on empty input generators, eliminating the `IndexError: list index out of range` and returning clean HTTP 200 with `segments: []`.

3. **Graceful Zero-Speech Secondary Format Generation in PowerShell**:
   - Changed the validation in `src/whisper-asr-service-docker.ps1` from falsy check `if (-not $ApiResult.segments)` to explicit null check `if ($null -eq $ApiResult.segments)`.
   - When `$ApiResult.segments.Count -eq 0`, emits a clear warning (`No active speech or segments detected in audio...`) and generates clean empty downstream transcript files (`.txt`, `.srt`, `.vtt`, `.tsv`, `.NOTES.md`, `.SUMMARY.md`).
   - Ensures the batch directory check recognizes the file as processed, preventing infinite retry loops across batch runs.

---

## Consequences

### Positive
* **Zero Batch Failures on Silent Media**: Media recordings with no detected speech no longer crash the API or abort folder processing.
* **Accurate Batch Completion State**: Valid blank transcripts are produced, so subsequent runs correctly identify the recording as processed.
* **Actionable User Awareness**: Red console warning informs users why a recording was processed with default telephony settings and encourages standard `.LL-X#` tagging.

### Negative
* Non-speech files still proceed to LLM summarization stages if enabled; however, LLM prompts gracefully handle empty transcript inputs and generate succinct notes noting the absence of conversational dialogue.
