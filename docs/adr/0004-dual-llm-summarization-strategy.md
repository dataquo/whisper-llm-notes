# ADR 0004: Dual LLM Summarization Strategy (NOTES.md vs SUMMARY.md)

## Status
Accepted

## Context
Audio transcripts vary widely in detail and purpose. Users often require two distinct levels of synthesis:
1. **Detailed Structured Notes**: Comprehensive action items, speaker contributions, decision logs, and timestamps.
2. **Executive Summary**: High-level, concise summary for fast scanning.

Running two different LLM backends (e.g., a high-parameter remote model on LM Studio and a local lightweight Ollama model) requires clear separation of output files and independent generation controls.

## Decision
1. **Distinct Output Formats**:
   * **`{basename}.NOTES.md`**: Generated via OpenAI-compatible endpoint (LM Studio / remote model). Contains detailed structured notes, speaker attributions, and timestamps.
   * **`{basename}.SUMMARY.md`**: Generated via Ollama REST API. Contains a concise summary.
2. **Selective Execution (`-GenerateMode`)**:
   * Accepts `both`, `notes`, or `summary`.
   * If only `NOTES.md` is missing, only `NOTES.md` is generated without re-transcribing or re-generating `SUMMARY.md`.
3. **VRAM Optimization**:
   * Ollama models are explicitly unloaded from VRAM (`ollama stop <model>`) after processing to free GPU memory for subsequent Whisper ASR passes.

## Consequences
### Positive
* No duplicate work: Skips existing summaries and generates only missing markdown files.
* Independent LLM engines: Can mix local Ollama models and remote LM Studio instances seamlessly.
* VRAM stability: Prevents GPU out-of-memory errors across large batch transcription jobs.
