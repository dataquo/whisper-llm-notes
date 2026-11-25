# WHISPER Operational Runbook & Workflow Guide

This guide provides practical instructions for daily operations, troubleshooting, testing, and developing within the **whisper-llm-notes** repository (v07.03).

---

## 1. Daily Operations

### Interactive Help & Parameter Discovery
Whenever you need a quick reminder of supported switches, parameter aliases, or filename tagging syntax:

```powershell
# View full help with complete filename convention syntax and parameter details
Get-Help .\src\_MASTER_WHISPER.ps1 -Full

# View ready-to-run copy-paste command examples
Get-Help .\src\_MASTER_WHISPER.ps1 -Examples

# Fast terminal syntax reminder
.\src\_MASTER_WHISPER.ps1 -?
```

* **IntelliSense Auto-Completion**: In PowerShell 7+, type `.\src\_MASTER_WHISPER.ps1 -` and press <kbd>Tab</kbd> or <kbd>Ctrl</kbd>+<kbd>Space</kbd> to inspect available switches and aliases interactively.

### Batch Processing a Directory
To transcribe all pending recordings in a folder:
```powershell
# Run from repository root (automatically triggers DJI video pre-processing if available)
pwsh -File .\src\_MASTER_WHISPER.ps1 -InputFolder "D:\Recordings\2026-August"
```

* The script automatically invokes `..\DJI\convert_DJI_videos_with_MetaData.ps1` with dynamic platform-aware hardware decoding (`special-quality-hw-opt-Apple_M2` on macOS or `special-quality-hw-dec-cuda` on Windows) and `-checkAudioSilence "0"` prior to scanning.
* The script automatically skips any audio file whose transcripts (`.json`, `.txt`, `.srt`, `.tsv`, `.vtt`, `.NOTES.md`, `.SUMMARY.md`) already exist and are non-empty.
* Converted WebM files (`*.CRF-*_LIBSVT-AV1*.webm`) are automatically suppressed if original source media is present.
* If only markdown notes are missing, it selectively runs LLM inference without re-running audio transcription.

### Video Pre-Processing Controls
* **Skip Video Pre-Conversion**:
  ```powershell
  pwsh -File .\src\_MASTER_WHISPER.ps1 -InputFolder "D:\Recordings" -SkipDJI
  ```
  *(Aliases: `-SkipDJI`, `-NoDJI`, `-SkipDJIConversion`)*

* **Custom DJI Conversion Script Path**:
  ```powershell
  pwsh -File .\src\_MASTER_WHISPER.ps1 -InputFolder "D:\Recordings" -DjiScriptPath "C:\Tools\convert_DJI_videos_with_MetaData.ps1"
  ```

* **Custom DJI Video Conversion Scene / Profile**:
  ```powershell
  pwsh -File .\src\_MASTER_WHISPER.ps1 -InputFolder "D:\Recordings" -DjiScene "special-quality-hw-opt-Apple_M2"
  ```
  *(Aliases: `-DjiScene`, `-DjiProfile`)*

### Selective LLM Execution Switches
* **Only Ollama Summary (`.SUMMARY.md`)**:
  ```powershell
  pwsh -File .\src\_MASTER_WHISPER.ps1 -InputFolder "D:\Recordings" -OnlyOllama
  ```
  *(Aliases: `-OnlyOllama`, `-OnlyOlama`, `-OllamaOnly`)*

* **Only LM Studio Notes (`.NOTES.md`)**:
  ```powershell
  pwsh -File .\src\_MASTER_WHISPER.ps1 -InputFolder "D:\Recordings" -OnlyLMStudio
  ```
  *(Aliases: `-OnlyLMStudio`, `-OnlyLM`, `-LMStudioOnly`)*

* **Pure WhisperX Transcription (No LLMs)**:
  ```powershell
  pwsh -File .\src\_MASTER_WHISPER.ps1 -InputFolder "D:\Recordings" -DisableLLM
  ```
  *(Aliases: `-DisableLLM`, `-DisableLLMs`, `-SkipLLM`, `-NoLLM`)*

### Single File Transcription
To transcribe or re-process a specific audio file directly with the execution engine:
```powershell
pwsh -File .\src\whisper-asr-service-docker.ps1 `
    -FilePath "D:\Recordings\corridor_camera.SK-E2.mp4" `
    -Profile echoed `
    -Language sk `
    -MinSpeakers 2 `
    -MaxSpeakers 2 `
    -GenerateMode both `
    -DebugMode
```

---

## 2. IP Security Camera Audio Optimization (Hikvision / HiLook)

When transcribing CCTV audio captured in reverberant spaces (concrete hallways, stairwells):

### Recommended Camera Settings (Web UI / iVMS-4200):
1. Navigate to: **Configuration $\to$ Video/Audio $\to$ Audio**.
2. **Audio Encoding**: Change from `G.711ulaw` (8 kHz) to **`AAC`** (or `MP2L2`).
3. **Sampling Rate**: Set to **`16 kHz`** (or 32/44.1 kHz if available).
4. **Audio Stream Bitrate**: Set to **`64 kbps`** or **`128 kbps`**.
5. **Environmental Noise Filtering**: Toggle to **`ON`** (activates hardware DSP filter on camera DSP chip).
6. **Input Volume**: Reduce from 100% to **`60 – 70%`** (prevents microphone diaphragm clipping in reverberant corridors).

### Impact on Whisper ASR Accuracy:
* **8 kHz G.711u**: Max frequency ~3.7 kHz. Slovak sibilants (*s, š, c, č, z, ž, f, t*) are cut off, forcing the model to guess words.
* **16 kHz AAC**: Preserves frequencies up to 8.0 kHz, providing full phonetic resolution for 95%+ transcription accuracy.

---

## 3. Local Machine Configuration (`config.local.json`)

To customize settings for your individual developer environment without modifying tracked repository files:

1. Copy `config/config.local.json.example` to `config/config.local.json`:
   ```powershell
   Copy-Item "config/config.local.json.example" "config/config.local.json"
   ```
2. Adjust properties specific to your machine (e.g. your local container name or remote LM Studio host):
   ```json
   {
     "whisper_service": {
       "docker_container_name": "whisperx-api"
     },
     "lm_studio_service": {
       "api_url": "http://192.168.1.50:1234/v1/chat/completions"
     }
   }
   ```
3. `config/config.local.json` is ignored by Git (`.gitignore`), ensuring your machine configuration is never committed.

---

## 4. macOS Apple Silicon (M2 Max) Setup & Native GPU Operations

Starting with **v07.00**, WHISPER runs natively on **macOS Apple Silicon (M1/M2/M3/M4)** with 100% Metal & MPS GPU acceleration using the exact same PowerShell scripts.

### A. Prerequisites & One-Command Setup
1. Clone or pull the repository on your Mac.
2. Ensure you have your Hugging Face read token ready.
   > [!IMPORTANT]
   > **Use a Classic Read Token (NOT a Fine-Grained Token)**: PyAnnote 3.1 is a composite pipeline that dynamically downloads sub-dependencies (e.g. `pyannote/wespeaker-voxceleb-resnet34-LM`). Fine-grained tokens restricting access to only `speaker-diarization-3.1` and `segmentation-3.0` fail at runtime. Generate a **Classic Token** with **Read** permission at [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens).
   > Also ensure you have accepted the user conditions on **both** gated models:
   > 1. [pyannote/speaker-diarization-3.1](https://huggingface.co/pyannote/speaker-diarization-3.1)
   > 2. [pyannote/segmentation-3.0](https://huggingface.co/pyannote/segmentation-3.0)
3. Set your token in the canonical configuration file at `macos/.env`:
   ```bash
   echo 'HF_TOKEN="hf_your_classic_token_here"' > ./macos/.env
   ```
4. Run the automated setup script:
   ```bash
   chmod +x ./macos/setup_macos.sh
   export HF_TOKEN="hf_your_classic_token_here"
   ./macos/setup_macos.sh
   ```
   * Installs `ffmpeg`, `pwsh`, and `python3` via Homebrew if missing.
   * Creates `./macos/.venv` and installs `mlx-whisper`, `torch` (with MPS), `whisperx`, and `pyannote.audio`.
   * Automatically converts the Slovak fine-tuned model (`kinit/whisper-large-v3-sk`) to MLX format at `~/.cache/whisper-mlx/whisper-large-v3-kinit-sk-mlx`.
   * Prepares `config/config.local.json` with `"docker_container_name": "native-mlx"`.

### B. Starting the Native M2 Max GPU Whisper Service
Start the FastAPI server on port 9000:
```bash
source ./macos/.venv/bin/activate
python ./macos/whisperx_mlx_server.py
```
*(Optionally run via `nohup` or `launchd` in the background).*

### C. Running Batch Transcription in macOS PowerShell
In your terminal, launch PowerShell 7 (`pwsh`) and run:
```powershell
pwsh -File ./src/_MASTER_WHISPER.ps1 -InputFolder ~/Recordings -SkipDJI
```

### D. Model Caching with LM Studio on macOS
If you downloaded `mlx-community/whisper-large-v3-mlx` inside LM Studio, the server automatically detects and loads from `~/.lmstudio/models/mlx-community/whisper-large-v3-mlx` to save disk space and bandwidth.

### E. Dedicated macOS Unit Tests
A dedicated test suite validates cross-platform macOS functionality without requiring Docker or CUDA:
```powershell
Invoke-Pester -Path ./tests/macos-crossplatform.Tests.ps1 -Output Detailed
```
Tests binary name resolution (`ffmpeg`/`curl`), hardware telemetry schemas (`sysctl`/`sw_vers`), `native-mlx` lifecycle handling, local config deep-merging, and cross-platform `Join-Path` path evaluation.

---

## 5. Docker & Backend Services Management

### Starting the WhisperX Service
The execution engine automatically starts the container if stopped (`auto_restart_container: true`). To start it manually:
```powershell
docker start whisper-asr-service
# Or if your container is named whisperx-api:
docker start whisperx-api
```

### Checking Service Health
```powershell
# Test WhisperX API
curl.exe -s http://localhost:9000/docs

# Test Ollama API
curl.exe -s http://localhost:11434/api/tags

# Test LM Studio Endpoint
curl.exe -s http://10.0.0.162:1234/v1/models
```

### Auditing Pipeline & Container Telemetry in `.log` Files
Every transcription run produces a JSON execution log (`{basename}.WHISPER.YYYYMMDD-HHmmss.log`). To inspect the runtime environment, script version, and Docker container details from PowerShell:

```powershell
# Parse the latest transcription log as JSON
$log = Get-Content .\Recordings\meeting.WHISPER.*.log -Tail 100 | Out-String | ConvertFrom-Json

# Inspect script version and execution identity
$log | Select-Object script_name, script_version, execution_time

# Inspect Docker container environment
$log.container_information | Format-List

# Inspect ASR decoding parameters & model
$log.api_parameters
$log.configuration_parameters
```

---

## 5. Local Development & Testing

### Running Pester Unit Tests
To verify all regex parsers, formatters, configuration loaders, and lifecycle logic:
```powershell
Invoke-Pester -Path ./tests -Output Detailed
```

### Running Static Code Analysis (Linter)
To check PowerShell scripts against project rules:
```powershell
Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

---

## 6. Git & Release Workflow

### Committing & Pushing
> [!IMPORTANT]
> All commits, merges, and pushes are performed manually by the human developer via **GitHub Desktop**. The AI agent is strictly forbidden from running `git commit`, `git push`, or `git tag`.

1. Open **GitHub Desktop**.
2. Review modified files in the **Changes** tab.
3. Enter a clear commit message.
4. Click **Commit to main** and then **Push origin**.

---

## 7. Troubleshooting Guide

| Problem | Cause | Solution |
| :--- | :--- | :--- |
| `Cannot restart container: '...' not found` | Local container name differs from `config.default.json` | Set `"docker_container_name"` in `config/config.local.json`. |
| `Container metadata fields (image, cudnn) are null in log` | Docker daemon unreachable or non-standard container name | Ensure Docker is running. The engine automatically attempts fallback inspection on `whisperx-api` and `whisper-asr-service`. |
| `Model hallucinates parliamentary phrases` | Slovak fine-tuned model (`kinit-sk`) running on muffled echo audio | Switch filename tag from `.SK-H2` to `.SK-E2` (`echoed` profile uses neutral OpenAI `large-v3`). |
| `Repeating word loops ("na päťkrát...")` | Low acoustic clarity causing beam search loop | Handled automatically in profile `echoed` (`beam_size=1`, `repetition_penalty=1.2`). |
| `GPU Out of Memory (CUDA OOM)` | Ollama or other LLMs retaining GPU VRAM | Whisper engine automatically restarts the container. Or run `ollama stop <model>`. |
| `Audio preprocessing yielded empty/invalid stream` | Video file has no audio stream or corrupt track | Input file contains no sound. Check FFmpeg log (`.log`) in target directory. |
| `Opening greetings have no speaker label ([NONE])` | PyAnnote left-edge receptive field boundary deficit on immediate speech | Enable `"lead_in_silence_seconds": 1.5` in profile configuration to prepend lead-in padding (see ADR 0010). |
| `Single speaker label covers both question and answer` | Trailing word stretched across pause into next speaker's turn by Wav2Vec2 | Inherent limitation of Wav2Vec2 forced alignment without VAD token. See detailed analysis in ADR 0010. |
| `Accented characters stripped from text` | Windows-1252 / UTF-8 encoding mismatch in regex | Enforce UTF-8 without BOM (`$Utf8NoBom`) and use unicode escapes (`\u2013\u2014`) in regex cleaners. |
| `MetadataError: parameter alias conflict` | Case-insensitive alias collision in PowerShell | Resolved in v06.01; ensure all parameters use clean, distinct aliases. |
| `Transcription failed with exit code: 26` (commas in path) | `curl` interprets commas (`,`) in audio file path as multi-file delimiters | Fixed in v07.00: File paths passed to `curl` multipart arguments are safely wrapped in escaped quotes (`-F "audio_file=@\"$Path\""`). |
| `Transcription failed with exit code: 26` (Windows UNC shares) | Windows `curl.exe` argument unescaping turns `@"\\` into an escaped quote sequence, corrupting UNC roots (`\server\share`) | Fixed in v07.02: Paths are normalized to forward slashes (`//server/share/...`) prior to curl invocation. Windows natively resolves forward-slash UNC paths. |
| `Whole recording transcribes into one line: "Thank you"` or repeats "Thanks for watching" | Low SNR audio amplified by `dynaudnorm` triggers Whisper's hallucination cascade when `condition_on_previous_text=true` | Fixed in v07.02: Disabled `condition_on_previous_text`, set `hallucination_silence_threshold=2.0`, added speech floor in Stage 0 VAD, and pruned unaligned phantom tokens after alignment. |
| `Device creation failed: -12 ... device type cuda needed for codec h264` | `_MASTER_WHISPER.ps1` hardcoded `-scene special-quality-hw-dec-cuda` on macOS | Fixed in v07.02: Master orchestrator dynamically selects `special-quality-hw-opt-Apple_M2` on macOS and `special-quality-hw-dec-cuda` on Windows. |
| `Diarization failed: 'NoneType' object has no attribute 'to'` | Fine-grained Hugging Face token lacks access to sub-dependency `pyannote/wespeaker-voxceleb-resnet34-LM` or terms not accepted | Use a **Classic Read Token** at [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens). Also accept user terms on both `speaker-diarization-3.1` and `segmentation-3.0`. |
| `[HF Token Auth Failed] Invalid user token` | Stale or unquoted token in root `.env` or missing permissions | Ensure token is placed in `macos/.env` without extra quotes or spaces. Check startup banner diagnostics. |
| `WeightsUnpickler error: Unsupported global: omegaconf.listconfig.ListConfig` | PyTorch 2.6 defaults `torch.load` to `weights_only=True` | Fixed in v07.00: `whisperx_mlx_server.py` registers safe OmegaConf globals and defaults `weights_only=False` for local model checkpoints. |
| `PSScriptAnalyzer warnings` | Formatting or syntax violation | Run `Invoke-ScriptAnalyzer -Path ./src` and fix flagged lines. |
| `Processed audio file not found` / missing FFmpeg log warnings on files with `[...]` | PowerShell `-Path` treating square brackets as wildcard globbing pattern | Enforce `-LiteralPath` across all PowerShell provider cmdlets (`Test-Path`, `Get-Content`, `Move-Item`, `Get-Item`). Resolved in v06.04 (see ADR 0012). |
| `FFmpeg stalls at EOF with 'Packet corrupt', 'partial file', or 'Input/output error'` | Truncated video cut-point (`.cutfile.`) or external storage read timeout at end of stream | Handled automatically in v07.01 via `-err_detect ignore_err -fflags +genpts+igndts+discardcorrupt` and `-vn` (see ADR 0016). Non-fatal corrupt packets are dropped immediately. |
| `Audio conversion speed starts at ~25x but slows to ~7x` | FFmpeg cumulative speed averaging, single-core CPU DSP limits, or external drive (`/Volumes/...`) bus saturation | Audio DSP runs on 1 CPU core; reading/writing to external drives saturates USB/network bandwidth. Using `-vn` (v07.01) bypasses video demuxing, sustaining 20x–25x on local SSDs. |