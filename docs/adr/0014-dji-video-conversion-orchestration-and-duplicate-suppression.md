# ADR 0014: External DJI Video Conversion Orchestration, CRF WebM Suffix Matching, and Duplicate Media Suppression

## Status
Accepted (v06.06)

## Context
High-resolution video captures from DJI hardware (drones, Action cameras, Osmo Pocket) and desktop captures (e.g. 5120x1440 ultrawide recordings) produce large H.264/HEVC MP4 files. The external companion script `..\DJI\convert_DJI_videos_with_MetaData.ps1` exists to transcode these files into compact AV1/Opus WebM containers with hardware-accelerated CUDA decoding (`-hwaccel cuda`), SVT-AV1 preset 2 software encoding, and metadata transfer via `exiftool`.

Users require an integrated batch workflow where running `src/_MASTER_WHISPER.ps1` against an input directory:
1. First executes the external DJI video conversion script on the directory with profile `special-quality-hw-dec-cuda` and audio silence detection disabled (`-checkAudioSilence "0"`).
2. Subsequently scans the directory to transcribe audio recordings using WhisperX and generate meeting notes / executive summaries.

Under this integration, several critical architectural and operational challenges were identified.

---

## Problem Analysis

### 1. Architectural Decoupling & External Script Delegation
According to **AGENTS.md** and **GEMINI.md**, `src/_MASTER_WHISPER.ps1` must remain a pure batch orchestrator. It must never embed raw FFmpeg execution, DSP filter graphs, Docker container management, or direct media encoding logic. Invoking video conversion must be accomplished strictly through external delegation without duplicating encoding logic.

### 2. Candidate Script Path Portability
The external script lives outside the repository root at `..\DJI\convert_DJI_videos_with_MetaData.ps1`. Depending on whether the user invokes PowerShell from the repository root, from `src/`, or from an arbitrary working directory, relative path resolution can break. A robust candidate discovery mechanism is necessary.

### 3. The Duplicate Ingestion Trap
`convert_DJI_videos_with_MetaData.ps1` produces output files with the naming pattern:
```text
<BaseName>.CRF-<crf>_<parametersVideoSufix>_<resolution>.webm
```
For example:
```text
2026-10-10 PerDiemoEU...EN-M1.CRF-44_LIBSVT-AV1_P2_SO_HW-DEC-CUDA_5120x1440.webm
```
Because `_MASTER_WHISPER.ps1` supports `.webm` as a valid audio format, scanning the directory after video conversion detected **both** the original `.mp4` and the newly generated `.webm`. This resulted in double transcription of the exact same audio, doubling GPU runtime and LLM API cost.

### 4. Tag Corruption and Untagged Warnings on Converted Files
When the video conversion script appends `.CRF-44_LIBSVT-AV1_...` to the base filename, the parameter tag (e.g. `.EN-M1`) is no longer adjacent to the file extension (`.webm`). Naive regex parsing in `Parse-FileNameParameters` failed to detect `.EN-M1`, causing the duplicate `.webm` to be treated as untagged, falling back to the telephony profile (`phone`) with auto-detected language instead of English meeting mode (`meeting`).

### 5. Suffix Regex Mismatch (`_CRF` vs `.CRF-`)
An initial suppression heuristic checked for `_CRF\d+.*LIBSVT-AV1`. However, in real-world DJI script output:
- The suffix begins with a dot (`.CRF`), not an underscore.
- The CRF tag contains a hyphen (`CRF-44`), not raw digits (`CRF44`).
Consequently, the duplicate `.webm` bypassed suppression and was queued for transcription.

---

## Decision & Evaluation of Alternatives

### Alternative 1: Remove `.webm` from Supported Audio Extensions
* *Mechanism*: Drop `.webm` from `$AudioExtensions` in `_MASTER_WHISPER.ps1`.
* *Pros*: Instantly eliminates duplicate processing of WebM video transcodes.
* *Cons*: Breaks valid workflows where users have legitimate standalone WebM voice notes or web recordings without MP4 source files.
* *Verdict*: **Rejected**.

### Alternative 2: Hardcode Absolute Paths to the DJI Conversion Script
* *Mechanism*: Require an exact absolute path to `convert_DJI_videos_with_MetaData.ps1`.
* *Pros*: Simple string invocation.
* *Cons*: Brittle; fails when repositories are cloned onto different drive letters, portable storage, or running in automated test/CI environments.
* *Verdict*: **Rejected**.

### Selected Strategy: Multi-Tiered Discovery, Suffix Normalization & Duplicate Suppression (Accepted)

#### 1. Multi-Tiered Candidate Script Resolution (`Get-DjiScriptPath`)
`_MASTER_WHISPER.ps1` resolves the conversion script across multiple standard candidate locations:
1. Explicit path parameter (`-DjiScriptPath`).
2. Parent relative path: `Join-Path (Split-Path $PSScriptRoot -Parent) "..\DJI\convert_DJI_videos_with_MetaData.ps1"`.
3. Script root relative path: `Join-Path $PSScriptRoot "..\..\DJI\convert_DJI_videos_with_MetaData.ps1"`.
4. Working directory relative path: `Join-Path (Get-Location) "..\DJI\convert_DJI_videos_with_MetaData.ps1"`.

If the script is not found, the orchestrator logs a gray notice and continues normal audio transcription without failing.

#### 2. Clean CLI Bypass Switch (`-SkipDJI`)
Users can bypass video conversion at any time using `-SkipDJI` (aliases: `-NoDJI`, `-SkipDJIConversion`).

#### 3. Strict Invocation Contract (`Invoke-DjiConversion`)
When invoked, the orchestrator passes the exact required arguments:
```powershell
& $resolvedScript -sourceFolder $resolvedFolder -scene "special-quality-hw-dec-cuda" -checkAudioSilence "0"
```
- `-scene "special-quality-hw-dec-cuda"`: High-quality SVT-AV1 preset 2 encoding with hardware CUDA decoding.
- `-checkAudioSilence "0"`: Explicitly disables silence cutoff/trimming to preserve complete audio duration.

#### 4. Resilient Duplicate Media Suppression
The candidate filtering in `_MASTER_WHISPER.ps1` checks for video conversion signatures using:
```powershell
if ($_.Name -match '(\.CRF-\d+|_CRF\d+|[\._]LIBSVT-AV1)') {
    $baseWithoutDjiSuffix = $_.Name -replace '(\.CRF-\d+|_CRF\d+|[\._]LIBSVT-AV1).*$', ''
    $hasOriginalMedia = $false
    foreach ($candExt in @(".mp4", ".mov", ".m4a", ".flac", ".mp3", ".webm")) {
        $candPath = Join-Path $_.DirectoryName "$baseWithoutDjiSuffix$candExt"
        if ($candPath -ne $_.FullName -and (Test-Path -LiteralPath $candPath)) {
            $hasOriginalMedia = $true
            break
        }
    }
    if ($hasOriginalMedia) { return $false }
}
```
- If an original media file with matching base name (`.mp4`, `.mov`, `.m4a`, etc.) exists in the folder, the converted `.webm` is excluded from audio processing.
- If the original media file does NOT exist (e.g. user deleted the 4K MP4 after transcode), the `.webm` is retained for transcription.

#### 5. Suffix-Resilient Parameter Tag Extraction
`Parse-FileNameParameters` strips transcode metadata before testing the naming convention regex:
```powershell
$EffectiveFileName = $FileName -replace '(\.CRF-\d+|_CRF\d+|[\._]LIBSVT-AV1)[^\.]*(\.[^.]+)$', '$2'
```
This ensures that `2026-10-10 PerDiemoEU.EN-M1.CRF-44_LIBSVT-AV1_...webm` normalizes to `2026-10-10 PerDiemoEU.EN-M1.webm`, properly resolving language `en`, profile `meeting`, and speaker count `1`.

---

## Consequences

### Positive
* **Seamless End-to-End Batch Workflow**: Video compression and audio transcription execute consecutively in a single command.
* **Zero Duplicate Transcriptions**: Converted `.webm` files never trigger redundant transcription when original media is present.
* **Tag Preservation**: Standalone converted files maintain parameter tags without defaulting to telephony profile or triggering false warnings.
* **Architectural Decoupling Preserved**: `_MASTER_WHISPER.ps1` remains free of FFmpeg DSP code and Docker lifecycle management.

### Negative
* If the user renames the source `.mp4` during or after conversion such that the base name no longer matches the `.webm`, suppression cannot correlate the two files and both may be queued.
