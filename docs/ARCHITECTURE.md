# WHISPER Technical Architecture & Design

This document details the end-to-end technical architecture, data processing pipeline, profile definitions, and service integrations of the **WHISPER** project (v06.04).

---

## 1. System Overview

WHISPER is a modular, high-throughput batch audio transcription and AI summarization pipeline designed for Windows environments. It bridges PowerShell automation with local/remote containerized inference engines:

```mermaid
flowchart TD
    A["Raw Media Input\n(.m4a, .mp3, .flac, .mp4)"] --> B["_MASTER_WHISPER.ps1\n(Batch Orchestrator)"]
    
    subgraph ParameterExtraction["1. Parameter Extraction & Batch Evaluation"]
        B --> C["Parse-FileNameParameters\n(Regex: .LL-X#)"]
        C --> D["Get-MissingMdFiles\n(Check: .NOTES.md, .SUMMARY.md)"]
    end
    
    subgraph EngineLifecycle["2. Engine & Container Management"]
        D --> E["whisper-asr-service-docker.ps1\n(Execution Engine)"]
        E --> F["Get-PipelineConfig\n(Deep Merge: default + local.json)"]
        F --> G["Ensure-WhisperContainerRunning\n(docker start + /health poll)"]
    end

    subgraph AudioPreprocessing["3. Preprocessing (FFmpeg)"]
        G --> H["FFmpeg Audio Pipeline\n(-ac 1 Mono + Bandwidth Filter + adelay Priming + Notch EQ + Loudnorm)"]
        H --> I["Temp Preprocessed Audio\n(.WAV / .MP3 16kHz, Length > 1KB)"]
    end
    
    subgraph ASRTranscription["4. Speech Recognition (WhisperX Docker)"]
        I --> J["WhisperX API POST\n(http://localhost:9000/asr)"]
        J --> K["Verbose JSON Response\n(Segments + Word Timestamps + Diarization)"]
        K --> K2["Adjust-TranscriptTimestamps\n(Compensate Lead-in Offset, Floor 0.0s)"]
    end

    subgraph MultiFormatGeneration["5. Format Re-generation (RAM)"]
        K2 --> L["JSON Transcript (.json)"]
        K2 --> M["Speaker Formatted TXT (.txt)"]
        K2 --> N["SRT Subtitles (.srt)"]
        K2 --> O["WebVTT Subtitles (.vtt)"]
        K2 --> P["TSV Data Table (.tsv)"]
    end

    subgraph AISummarization["6. Context-Aware AI Summaries (Optional)"]
        M --> Q["LM Studio API\n(http://10.0.0.162:1234/v1)"]
        Q --> R["Detailed Notes (.NOTES.md)"]
        M --> S["Ollama API\n(http://localhost:11434)"]
        S --> T["Executive Summary (.SUMMARY.md)"]
    end

    subgraph ResourceOptimization["7. GPU Resource Cleanup"]
        K --> U["Restart-WhisperContainer\n(docker restart & flush VRAM)"]
        R & T --> V["Ollama Model VRAM Unload\n(ollama stop)"]
    end
```

---

## 2. Decoupled Script Responsibilities

The codebase enforces strict separation of concerns between batch folder iteration and single-file pipeline execution:

### A. `src/_MASTER_WHISPER.ps1` (Pure Batch Orchestrator)
* **Folder Scanning**: Discovers original media files (`.m4a`, `.flac`, `.mp4`, `.mp3`) and excludes intermediate normalized files.
* **Tag Parsing**: Extracts language, DSP profile, and speaker counts from filename suffixes (`file.LL-X#.ext`, supporting `P`, `M`, `D`, `H`, `E`).
* **Missing Output Inspection**: Checks for existing `.json`, `.txt`, `.srt`, `.tsv`, `.vtt`, `.NOTES.md`, and `.SUMMARY.md` files.
* **Targeted Dispatch**: Computes the exact `GenerateMode` (`both`, `notes`, `summary`, `none`) and honors `-OnlyOllama`, `-OnlyLMStudio`, or `-DisableLLM` flags.

### B. `src/whisper-asr-service-docker.ps1` (Self-Contained Execution Engine)
* **Configuration Layering**: Loads tracked `config.default.json` and deep-merges machine-specific `config.local.json`.
* **Container Lifecycle**: Manages Docker start, readiness polling (`/docs` or `/health`), and restart on completion or GPU error.
* **Audio DSP Normalization**: Preprocesses audio using FFmpeg with mono downmixing (`-ac 1`), notch EQ, and -16 LUFS loudness normalization.
* **WhisperX ASR**: Streams preprocessed audio to the container API with exact query parameters (`beam_size`, `condition_on_previous_text`, `repetition_penalty`).
* **Language-Aware Model Guard**: Restricts Slovak fine-tuned models (`kinit-sk`) to Slovak audio, falling back to multilingual `large-v3` for Czech and English.
* **Multi-Format Export & Deduplication**: Generates 5 transcript formats in system RAM while collapsing repeating acoustic stutter loops.
* **Context-Aware LLM Summarization**: Coordinates structured notes via LM Studio and executive summaries via Ollama with acoustic error correction prompts.
* **Telemetry & Hardware Profiling**: Collects CPU, RAM, and GPU hardware metrics via native CIM queries.

---

## 3. Audio Preprocessing Profiles (FFmpeg)

Each profile applies specialized DSP filter chains to optimize voice clarity before sending audio to WhisperX. All profiles enforce mono downmix (`-ac 1`) to ensure compatibility with multi-channel audio tracks (e.g. 5.1 or 7.1 HE-AAC):

| Profile | Tag | Suffix Identifier | Bandwidth & DSP Filters | Best For | Model Dispatched |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`phone`** | `P` | `PHONE-NORM_HP-LW-SP-LN` | Highpass: 200 Hz, Lowpass: 3500 Hz<br>`speechnorm=e=4:r=0.0001:l=1`<br>`loudnorm=I=-16:TP=-1.5:LRA=11`<br>*(Lead-in silence: 1.5s)* | Cell phone calls, landlines | `large-v3` |
| **`meeting`** | `M` | `MEETING-NORM_HP-LW-DN` | Highpass: 80 Hz, Lowpass: 8000 Hz<br>`dynaudnorm=p=0.9:m=50:s=5:g=15`<br>`loudnorm=I=-16:TP=-1.5:LRA=11` | Multi-person conference room meetings, webinars | `large-v3` |
| **`distant`** | `D` | `DISTANT-NORM_HP-LP-AC-SN` | Highpass: 200 Hz, Lowpass: 4000 Hz<br>`acompressor=threshold=-24dB:ratio=4`<br>`speechnorm=e=4:r=0.0001:l=1`<br>`loudnorm=I=-16:TP=-1.5:LRA=11` | Far-field microphones, noisy ambient environments | `large-v3` |
| **`hallway`** | `H` | `HALLWAY-NORM_HP-LP-DN-EQ` | Highpass: 220 Hz, Lowpass: 3700 Hz<br>`afftdn=nr=14:nf=-32:tn=1`<br>`equalizer=f=380:width_type=q:w=1.2:g=-4`<br>`loudnorm=I=-16:TP=-1.5:LRA=11` | Slovak corridor / hallway CCTV camera audio | `kinit-sk` (SK) / `large-v3` (CS/EN) |
| **`echoed`** | `E` | `ECHOED-NORM_HP-LP-DN-EQ` | Highpass: 220 Hz, Lowpass: 3700 Hz<br>`afftdn=nr=14:nf=-32:tn=1`<br>`equalizer=f=380:width_type=q:w=1.2:g=-4`<br>`loudnorm=I=-16:TP=-1.5:LRA=11` | Reverberant concrete rooms, universal multilingual echo | `large-v3` (Greedy Search, penalty=1.2) |

### Lead-in Silence & Diarization Priming (`lead_in_silence_seconds`)
For conversational telephone calls (`phone` profile), initial utterances often suffer from boundary edge defects in PyAnnote's sliding receptive window, leaving opening greetings unassigned (`speaker: null`).
* **FFmpeg Priming**: Setting `"lead_in_silence_seconds": 1.5` prepends `adelay=1500:all=1` to the preprocessed audio sent to WhisperX.
* **Timestamp Compensation**: The engine's `Adjust-TranscriptTimestamps` function subtracts 1.5s from all segment and word start/end timestamps (clamped to 0.0s) before generating `.json`, `.txt`, `.srt`, `.vtt`, and `.tsv` files, maintaining exact time alignment with the original media.

---

## 4. Configuration Layering Architecture

The configuration subsystem employs deep hierarchical layering:

```text
config/
├── config.default.json        # Base defaults (Tracked in Git)
├── config.local.json.example  # Template for machine overrides
└── config.local.json          # Machine-specific overrides (Ignored by Git)
```

### Deep Merge Behavior (`Get-PipelineConfig`):
1. `config/config.default.json` is loaded as the baseline.
2. If `config/config.local.json` (or a custom `-ConfigPath`) exists, each section and property is overlaid onto the baseline object.
3. Partial overrides (such as overriding only `docker_container_name` or `api_url`) retain all baseline filter chains, default models, and profile configurations.

---

## 5. Output Formats Generated in a Single Pass

To maximize GPU efficiency, the WhisperX API is invoked once to retrieve full diarized JSON data. PowerShell then reconstructs all secondary formats in RAM:

1. **`{basename}.json`**: Full raw WhisperX payload with word-level alignments, speaker IDs, and probabilities.
2. **`{basename}.txt`**: Clean transcript with speaker tags (e.g. `[SPEAKER_00]: Hello.`).
3. **`{basename}.srt`**: SubRip subtitle format with `00:00:00,000` timestamps and speaker labels.
4. **`{basename}.vtt`**: WebVTT subtitle format with `00:00:00.000` timestamps and speaker labels.
5. **`{basename}.tsv`**: Tab-separated value file (`start\tend\tspeaker\ttext`) for spreadsheet analysis.
6. **`{basename}.NOTES.md`**: Deep structured notes generated by LM Studio.
7. **`{basename}.SUMMARY.md`**: High-level executive summary generated by Ollama.
8. **`{basename}.WHISPER.YYYYMMDD-HHmmss.log`**: Complete execution telemetry and hardware metadata log.

---

## 6. ASR Decoding Optimization, Language Guards & LLM Acoustic Reconstruction

### A. Strict Decoding Configuration
To eliminate hallucination loops on distorted or reverberant audio, the `echoed` profile configures:
* **`beam_size = 1`**: Forces greedy search decoding, restricting the model to direct acoustic probabilities without hallucinating long speculative phrases.
* **`condition_on_previous_text = false`**: Stops acoustic errors in early segments from propagating into subsequent timestamps.
* **`repetition_penalty = 1.2` & `no_repeat_ngram_size = 3`**: Prevents repetitive looping on trailing reverberant echoes.

### B. Automatic Language Guard
In [src/whisper-asr-service-docker.ps1](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/src/whisper-asr-service-docker.ps1), if a profile specifies a Slovak fine-tuned model (e.g. `kinit-sk`):
* When `Language == 'sk'`, `whisper-large-v3-kinit-sk-ct2` is dispatched.
* When `Language == 'cs'` or `Language == 'en'`, the engine automatically falls back to baseline `large-v3` to prevent cross-lingual corruption.

### C. Context-Aware LLM Post-Reconstruction
For reverberant profiles (`hallway`, `echoed`), the LLM prompt templates for LM Studio and Ollama dynamically include acoustic reconstruction rules:
```markdown
ACOUSTIC CONTEXT & RECONSTRUCTION GUIDELINES:
- This recording was captured in a reverberant acoustic space with echo and distance (hallway/corridor camera).
- The raw transcript may contain phonetic misinterpretations, slurred syllables, or acoustic stuttering artifacts.
- In your structured notes/summary:
  1. Reconstruct the plausible and coherent meaning of sentences by correcting obvious phonetic transcription errors and grammatical agreements in the target language (Slovak / Czech / English).
  2. Filter out repeating filler loops or acoustic stutter fragments.
  3. Extract the underlying genuine conversation, intent, action items, and speaker exchanges clearly.
  4. Do not hallucinate unrelated facts; keep reconstructions strictly faithful to the conversational context.
```

---

## 7. Hardware Telemetry & Performance Metrics

On every transcription run, [src/whisper-asr-service-docker.ps1](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/src/whisper-asr-service-docker.ps1) gathers system hardware metrics via native CIM queries (`Get-CimInstance`) and calculates processing throughput:

* **Real-Time Factor (RTF)**:
  $$\text{RTF} = \frac{\text{Processing Time (s)}}{\text{Audio Duration (s)}}$$
  *(Values $< 1.0$ indicate faster-than-realtime transcription).*
* **Tokens Per Second (TPS)**:
  $$\text{TPS} = \frac{\text{Approximate Token Count}}{\text{Processing Time (s)}}$$
* **Hardware Inventory**: CPU cores, RAM modules, GPU driver version, motherboard model, and OS build recorded in JSON logs.

---

## 8. CLI Discovery & Comment-Based Help Architecture

As documented in [ADR 0009](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/docs/adr/0009-comment-based-help-and-cli-discovery.md), CLI parameter discoverability and filename convention hints are delivered through standard PowerShell Comment-Based Help (CBH) rather than runtime console banner overhead.

### Architectural Flow:
```mermaid
flowchart LR
    User["User Terminal"] -->|Get-Help / -? / Tab| Engine["PowerShell Help & AST Parser"]
    Engine -->|Parses on Demand| CBH["src/_MASTER_WHISPER.ps1 Header Block\n(.SYNOPSIS, .DESCRIPTION, .PARAMETER, .EXAMPLE)"]
    CBH -->|Renders| Out["Interactive Console Output\n- Full Filename Tagging Convention\n- DSP Profiles & Fallbacks\n- All Parameter Aliases\n- Practical Syntax Examples"]
```

### Supported Discoverability Commands:
* `Get-Help .\src\_MASTER_WHISPER.ps1 -Full`: Complete synopsis, parameter matrix, alias cross-references, and filename tag rules.
* `Get-Help .\src\_MASTER_WHISPER.ps1 -Examples`: Immediate copy-paste CLI examples.
* `.\src\_MASTER_WHISPER.ps1 -?`: Built-in quick terminal syntax reminder.
* <kbd>Tab</kbd> / <kbd>Ctrl</kbd>+<kbd>Space</kbd>: Auto-complete parameter discovery with dynamic alias resolution.

---

## 9. Telephone Diarization & Sub-Second Timestamp Compensation

As documented in [ADR 0010](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/docs/adr/0010-telephone-diarization-boundary-silence-and-alignment.md), telephone recordings frequently exhibit speaker diarization boundary anomalies caused by PyAnnote's left-edge receptive field deficit and Wav2Vec2 forced alignment silence stretching.

### Sub-Second Offset Compensation Flow:
1. **Configurable Lead-in Silence**: Profiles define `"lead_in_silence_seconds"` (default `1.5s` for `phone`, `0.0s` for others).
2. **FFmpeg Padding**: When `lead_in_silence_seconds > 0`, the engine prepends `adelay=$([int]($Offset * 1000)):all=1` to the preprocessed audio before upload to WhisperX.
3. **In-Memory Adjustment (`Adjust-TranscriptTimestamps`)**:
   - Subtracts `lead_in_silence_seconds` from all segment, word, and word-segment timestamps.
   - Enforces a zero floor (`[Math]::Max(0.0, [double]$timestamp - $offset)`).
   - Rounds all timecodes to 3 decimal places.
4. **Multi-Format Export Synchronization**: Compensated timestamps flow directly into `.json`, `.txt`, `.srt`, `.vtt`, and `.tsv`, guaranteeing 100% timecode synchronization with original source media.

---

## 10. Runtime Telemetry, Container Metadata & Service Auditing

As documented in [ADR 0011](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/docs/adr/0011-runtime-telemetry-and-container-metadata-auditing.md), production auditing requires explicit tracking of pipeline script versions, Docker container environments, and LLM inference endpoints to trace transcription fidelity across infrastructure updates.

### A. Dual-Property Script Identity & Version Resolution
The engine separates script identity from semantic versioning:
* **`script_name`**: Automatically extracted from `$MyInvocation.MyCommand.Path` (e.g. `whisper-asr-service-docker.ps1`).
* **`script_version`**: Evaluated via canonical constant `$ScriptVersionNumber = "v06.04"` with legacy backward compatibility if versioned script filenames (`*.vXX.YY.ps1`) are executed.

### B. Multi-Tier Container Metadata Discovery (`Get-WhisperContainerMetadata`)
The telemetry collector enforces a resilient 3-tier inspection strategy to guarantee complete metadata capture:

```mermaid
flowchart TD
    Start["New-TranscriptionLog Invoked"] --> Tier1["Tier 1: Docker CLI Inspect\n(Resolved Container: whisperx-api / whisper-asr-service)"]
    Tier1 -->|Success| PopulateAll["Extract Container Metadata:\n- container_name\n- image & short image_id\n- api_version (OpenContainers label)\n- cudnn_version (NVIDIA label)\n- status (running / healthy)"]
    Tier1 -->|NotFound / Failure| Tier2["Tier 2: Candidate Scan Fallback\n(Checks alternate: whisperx-api, whisper-asr-service)"]
    Tier2 -->|Found| PopulateAll
    Tier2 -->|NotFound / No Docker| Tier3["Tier 3: HTTP API Fallback\n(GET $ApiUrl/openapi.json)"]
    Tier3 -->|HTTP 200| PopulatePartial["Extract API Info:\n- api_version: info.version\n- status: online\n(Docker-specific fields set to null)"]
    Tier3 -->|Offline| PopulateOffline["status: offline"]
    PopulateAll --> WriteLog["Write Initial & Final JSON Log"]
    PopulatePartial --> WriteLog
    PopulateOffline --> WriteLog
```

### C. Logging Schema & Metadata Attributes
Every transcription generates a structured `.log` file containing:
* **`script_name` & `script_version`**: Exact pipeline release version (`v06.04`).
* **`container_information`**: Container name, image tag, image layer digest, internal API version, cuDNN version, and status.
* **`api_parameters`**: Language code and selected model name (`large-v3`, `kinit-sk`, etc.).
* **`configuration_parameters`**: Profile, diarization toggles, VAD thresholds, speaker bounds, lead-in silence seconds, and FFmpeg filter chains.
* **`system_information`**: CPU model, RAM modules, GPU driver, motherboard, and OS build.
* **`performance_metrics`**: Audio duration, processing time, RTF throughput, token count, and TPS.

### D. LLM Service Auditing (`.SUMMARY.md`)
During executive summary generation via Ollama, the engine dynamically queries `GET /api/version` (guarded by a 2-second timeout) and records the running Ollama version alongside model parameters in the summary footer table.

---

## 8. Filesystem Path Handling & Special Character Resilience

### Bracket and Globbing Immunity (`-LiteralPath`)
In media recording and web meeting capture workflows, filenames routinely feature bracketed prefixes and identifiers (e.g. `[DQ] [PD] Meet...`). 

In PowerShell, passing paths with square brackets `[` and `]` to default `-Path` parameters triggers wildcard globbing (evaluating characters inside `[...]` as character-class pattern sets). To guarantee zero false-positive file misses:
* **Strict `-LiteralPath` Standard**: All filesystem operations (`Test-Path`, `Get-Content`, `Move-Item`, `Get-Item`, `Remove-Item`) across `_MASTER_WHISPER.ps1` and `whisper-asr-service-docker.ps1` strictly bind paths using `-LiteralPath`.
* **Zero Input Alteration**: Original files and folders are never renamed or modified.
* **Deterministic Interoperability**: Paths are safely passed to external binaries (`ffmpeg.exe`, `curl.exe`) via quoted arguments without PowerShell wildcard expansion.
