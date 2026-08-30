# ADR 0003: Declarative Filename Metadata Tagging Convention

## Status
Accepted

## Context
When batch processing audio files from diverse sources (telephone calls, board meetings, ambient room recordings), each file requires specific parameters:
- Acoustic equalization and bandwidth filtering.
- Diarization speaker count bounds (`min_speakers` / `max_speakers`).
- Target transcription language (or auto-detection).

Manually specifying command-line flags for every individual file in a batch of dozens of recordings is inefficient and error-prone.

## Decision
Adopt a declarative filename suffix syntax:
```text
[title].[LANG]-[PROFILE][SPEAKERS].[ext]
```

### Grammar
* **`LANG`** (2 characters, optional): `CS` (Czech), `SK` (Slovak), `EN` (English), or omitted for Whisper auto-detection.
* **`PROFILE`** (1 character, optional):
  * `P` $\rightarrow$ `phone` (narrow bandwidth 200–3500 Hz, speech normalization).
  * `M` $\rightarrow$ `meeting` (wide range 80–8000 Hz, dynamic normalization).
  * `D` $\rightarrow$ `distant` (compression + adaptive noise reduction).
* **`SPEAKERS`** (integer, optional): Explicit diarization speaker count.

### Parsing Engine
* Implemented in `Parse-FileNameParameters` ([src/_MASTER_WHISPER.ps1](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/src/_MASTER_WHISPER.ps1)) and `Extract-ParametersFromFilename` ([src/whisper-asr-service-docker.ps1](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/src/whisper-asr-service-docker.ps1)).
* Validated with automated Pester 5 unit tests.

## Consequences
### Positive
* Zero-configuration batch processing: Simply rename input files and run `_MASTER_WHISPER.ps1`.
* Self-documenting files: Audio files explicitly declare their intended processing parameters.
* Safe fallbacks: Untagged files default cleanly to Phone profile with auto language detection.
