# ADR 0011: Runtime Telemetry, Container Metadata Auditing & Version Resolution

## Status
Accepted (v06.03)

## Context
As the WHISPER pipeline transitioned to a production-grade batch system, two operational transparency challenges emerged:

1. **Loss of Script Version in Logs**:
   In legacy releases (v04–v05), scripts were versioned via their filenames (e.g. `whisper-asr-service-docker.v04.06.ps1`), and the engine extracted `$ScriptVersion` using regex matching `v(\d+\.\d+)`. When v06.00 enforced the **Single Source of Truth** architectural standard (centralizing scripts into unversioned filenames like `src/whisper-asr-service-docker.ps1`), the filename regex failed to match. The script fell back to its raw filename, producing `"script_version": "whisper-asr-service-docker.ps1"` with no version number attached.

2. **Opaque Whisper & Container Runtime Environment**:
   Transcription logs (`.log`) recorded host hardware (CPU, RAM, GPU) and ASR decoding parameters (`model`, `diarize`, `vad_filter`, `ffmpeg_filters`), but lacked visibility into the actual containerized WhisperX engine:
   - Which Docker container executed the job?
   - What image repository and image digest tag was running?
   - What upstream WhisperX API version and internal NVIDIA cuDNN library were deployed inside the container?
   - What was the container's runtime state?

3. **Missing LLM Service Versioning**:
   While `SUMMARY.md` recorded the Ollama model name (`gemma3:4b`), it omitted the Ollama server runtime version.

Without this metadata, auditing historical transcription runs to trace behavioral changes across model revisions or Docker updates was impossible.

---

## Decision & Evaluation of Alternatives

### Option A: Re-introduce Versioned Filenames in `src/`
- *Mechanism*: Rename scripts back to versioned files (e.g. `whisper-asr-service-docker.v06.03.ps1`).
- *Pros*: Restores legacy filename regex extraction without changing code logic.
- *Cons*: **Violates Core Architectural Invariants**. Creates file proliferation, breaks master orchestrator references, disrupts CI/CD paths, and forces git history divergence. **Strictly Rejected**.

### Option B: Monolithic Version String in Logs
- *Mechanism*: Combine name and version into a single string: `"script_version": "whisper-asr-service-docker.v06.03"`.
- *Pros*: Preserves the legacy v04 single-string format.
- *Cons*: Blurs the distinction between file identity and semantic version; makes automated parsing, filtering, and database indexing more brittle.

### Option C: Split Fields + Multi-Tier Container Metadata Discovery + Ollama API Versioning [SELECTED]
- *Mechanism*:
  1. **Split Fields**: Introduce distinct, machine-readable JSON properties:
     - `"script_name": "whisper-asr-service-docker.ps1"`
     - `"script_version": "v06.03"`
     Governed by a canonical script constant `$ScriptVersionNumber = "v06.03"` while maintaining legacy filename regex compatibility if older versioned files are executed.
  2. **Multi-Tier Container Telemetry (`Get-WhisperContainerMetadata`)**:
     - **Tier 1 (Direct Docker CLI Inspect)**: Queries `docker inspect` using the container name resolved from deep configuration layering (`$AppConfig.whisper_service.docker_container_name`, e.g. `whisperx-api`). Extracts container name, image repository, short image SHA, OpenContainers API version label, cuDNN version label, and runtime status.
     - **Tier 2 (Candidate Scan Fallback)**: If the configured container name fails inspection, scans common Whisper container names (`whisperx-api`, `whisper-asr-service`) before giving up.
     - **Tier 3 (HTTP Network Fallback)**: If Docker CLI is unavailable (e.g. remote daemon or missing permissions), queries `$ApiUrl/openapi.json` to extract `api_version` and confirm online status.
  3. **Ollama Service Versioning**:
     - Dynamically queries `$OllamaEndpoint/api/version` (with a 2-second timeout guard) and appends `| Service Version | Ollama <version> |` to the `AI Processing Information` markdown table in `.SUMMARY.md`.

---

## Implementation Details

### 1. Script Version Detection
In [src/whisper-asr-service-docker.ps1](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/src/whisper-asr-service-docker.ps1):
```powershell
$ScriptVersionNumber = "v06.03"
$ScriptName = if ($MyInvocation.MyCommand.Path) {
    [System.IO.Path]::GetFileName($MyInvocation.MyCommand.Path)
} else {
    "whisper-asr-service-docker.ps1"
}

$ScriptVersion = if ($ScriptName -match "v(\d+\.\d+)(\.\d+)?\.ps1$") {
    "v$($Matches[1])"
} else {
    $ScriptVersionNumber
}
```

### 2. Configuration Forwarding & Container Telemetry
`New-TranscriptionLog` receives `$PipelineConfig` and invokes `Get-WhisperContainerMetadata`:
```powershell
function Get-WhisperContainerMetadata {
    param(
        [string]$ContainerName,
        [string]$ApiUrl,
        [PSCustomObject]$PipelineConfig
    )
    # 1. Resolve configured container name (e.g. from config.local.json)
    # 2. Execute docker inspect with fallback candidate scan
    # 3. Fallback to HTTP /openapi.json if Docker CLI is unavailable
}
```

### 3. Log Schema Structure
The resulting `.log` JSON structure:
```json
{
  "script_name": "whisper-asr-service-docker.ps1",
  "script_version": "v06.03",
  "execution_time": "2026-09-08 11:42:00.000",
  "day_of_week": "Tuesday",
  "container_information": {
    "container_name": "whisperx-api",
    "image": "learnedmachine/whisperx-asr-service:latest",
    "image_id": "sha256:1e12bddec948",
    "api_version": "0.3.1",
    "cudnn_version": "9.0.0.312",
    "status": "running"
  },
  "api_parameters": {
    "language": "sk",
    "model": "large-v3"
  },
  "configuration_parameters": { ... },
  "system_information": { ... },
  "performance_metrics": { ... }
}
```

---

## Consequences

### Positive
* **Full Auditability**: Every transcription log unambiguously identifies the pipeline script version, WhisperX container name, image digest, API version, and CUDA/cuDNN environment.
* **Resilient Discovery**: Configuration overrides (`whisperx-api` in `config.local.json`) are seamlessly respected, with automated candidate fallback preventing null values.
* **Zero Nulls in Standard Runs**: Eliminates empty telemetry fields when Docker is active while degrading gracefully to HTTP inspection on headless/remote setups.
* **Clean Markdown Tables**: Fixed table formatting across `.SUMMARY.md` and `.NOTES.md` with explicit Ollama service versions.
* **Single Source of Truth Maintained**: Version metadata is tracked cleanly in code and config without duplicating script files.

### Negative / Trade-offs
* `docker inspect` adds ~100–150 ms to the initial log creation phase (completely negligible compared to audio transcription duration).
* Docker inspect requires Docker CLI access in the user session; remote-only Docker setups rely on the HTTP `/openapi.json` fallback, which does not report `image_id` or `cudnn_version`.
