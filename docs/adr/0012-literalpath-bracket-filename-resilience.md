# ADR 0012: LiteralPath Enforcement for Bracket and Special Character Filename Resilience

## Status
Accepted (v06.04)

## Context
In real-world workflows, media files ingested into the WHISPER batch processing pipeline frequently originate from web meeting platforms, screen recorders, and capture utilities (e.g., Google Meet recordings, OBS Studio, Zoom, or manual archiving conventions). These filenames routinely feature square brackets `[` and `]`, tags like `[DQ]`, `[PD]`, dates, and whitespace:
```text
2026-11-05 [DQ] [PD] Meet - Workshop s Miky Škoda_ Kde se bere hodnota - Google Chrome 2026-11-05 18-02-36.CS-M4.mp4
```

During execution of the batch orchestrator (`src/_MASTER_WHISPER.ps1`) and single-file execution engine (`src/whisper-asr-service-docker.ps1`), the pipeline encountered fatal runtime breakages:
1. **False "Processed Audio File Not Found" Aborts**:
   FFmpeg successfully preprocessed the audio into `.mp3` format (`Success! Audio preprocessed successfully`). However, immediately afterwards, the engine evaluated:
   ```powershell
   if (-not (Test-Path "$TempProcessedFile")) { 
       Write-Error "Processed audio file not found: $TempProcessedFile"
       exit 
   }
   ```
   PowerShell returned `$false` for `Test-Path "$TempProcessedFile"`, halting execution before the WhisperX ASR API could be invoked.
2. **Missing FFmpeg Report Warnings**:
   `Test-Path $FFReportPath` and `Move-Item -Path $LogFileName -Destination $FFReportPath` failed to detect or relocate the generated FFREPORT log files, resulting in `WARNING: FFmpeg log file not found at expected location`.
3. **Broken Batch Dependency Detection**:
   In `src/_MASTER_WHISPER.ps1`, `Get-MissingMdFiles`, transcript checks, and file discovery loops (`Test-Path`, `Get-Content`, `Get-Item`) failed to recognize existing `.json`, `.txt`, `.srt`, `.NOTES.md`, and `.SUMMARY.md` files whenever parent folders or file names contained square brackets.

### Root Cause Analysis
In PowerShell, standard provider cmdlets (`Test-Path`, `Get-Content`, `Move-Item`, `Get-Item`, `Get-ChildItem`) bind positional string parameters to `-Path` by default. Under the `-Path` parameter, PowerShell treats square brackets `[` and `]` as wildcard globbing character sets (e.g., `[abc]` matching any single character among 'a', 'b', or 'c'). 

When evaluated via `-Path`, an expression such as `...\[DQ] [PD]...` is interpreted as:
- Match character 'D' or 'Q'
- Followed by space
- Followed by character 'P' or 'D'

Because the actual filesystem entry literally contained the literal bracket characters `[` and `]`, PowerShell's pattern matcher failed to match the literal filename and returned `$false`.

---

## Decision & Evaluation of Alternatives

### Option A: Escape Special Characters in Filenames via Regex/Backticks
- *Mechanism*: Pre-escape brackets in path strings (e.g., replace `[` with `` `[ `` or `[[]`).
- *Pros*: Could theoretically work without altering parameter names on cmdlets.
- *Cons*:
  - Highly brittle across external process invocations (`ffmpeg.exe`, `curl.exe`, `docker`).
  - Fails when backticks or escape characters are passed to .NET Framework methods (`[System.IO.File]`) or external CLI tools that interpret backticks literally.
  - Adds maintenance complexity and high cognitive overhead to every string interpolation.
- *Verdict*: **Rejected**.

### Option B: Restrict Input Filename Rules (Sanitization / Auto-Renaming)
- *Mechanism*: Automatically rename input files on disk to strip `[` and `]` before processing.
- *Pros*: Ensures filenames conform to traditional POSIX alphanumeric patterns.
- *Cons*:
  - **Violates User Data Invariants**: Modifying or renaming original user media files without consent is unacceptable in batch processing pipelines.
  - Breaks links to existing meeting archives, bookmarks, and external metadata systems.
- *Verdict*: **Rejected**.

### Option C: Universal `-LiteralPath` Enforcement Across All PowerShell File Cmdlets [SELECTED]
- *Mechanism*:
  Systematically replace `-Path` with `-LiteralPath` across all PowerShell provider cmdlets (`Test-Path`, `Get-Content`, `Move-Item`, `Get-Item`, `Remove-Item`, `Set-Content`) handling media files, intermediate audio, FFmpeg logs, transcript outputs, and markdown summaries.
- *Pros*:
  - **Zero Wildcard Interpretation**: Idiomatic PowerShell standard for treating every character (including `[`, `]`, `?`, `*`) exactly as literal text.
  - **Seamless Interoperability**: Preserves original filenames verbatim across external tools (`ffmpeg.exe`, `curl.exe`, `docker`) while ensuring PowerShell internal state inspection is 100% deterministic.
  - **Non-Destructive**: Leaves original user files and naming conventions untouched.
- *Verdict*: **Accepted & Enforced**.

---

## Detailed Implementation Specifics

### 1. Single-File Engine (`src/whisper-asr-service-docker.ps1`)
All filesystem inspection points for preprocessed audio, logs, neural enhancement, WPE outputs, and transcripts enforce `-LiteralPath`:
* `Test-Path -LiteralPath $TempProcessedFile` (both redundant conversion skipping and post-FFmpeg verification).
* `Test-Path -LiteralPath $OutputDir` (directory existence guard).
* `Test-Path -LiteralPath $LogFileName` / `Move-Item -LiteralPath $LogFileName` (FFmpeg report movement).
* `Test-Path -LiteralPath $FFReportPath` (FFmpeg report verification).
* `Test-Path -LiteralPath $EnhancedFile` / `Get-Item -LiteralPath $EnhancedFile` (Resemble Enhance neural audio stage).
* `Test-Path -LiteralPath $WpeOutputFile` / `Get-Item -LiteralPath $WpeOutputFile` (WPE statistical dereverberation stage).
* `Test-Path -LiteralPath "$FullBase.json"` (ASR caching guard).
* `Test-Path -LiteralPath $TranscriptPath` (transcription text reading for LLM prompt context).
* `Test-Path -LiteralPath "$FullBase.NOTES.md"` and `Test-Path -LiteralPath "$FullBase.SUMMARY.md"` (LLM markdown summarization guards).
* `Test-Path -LiteralPath $LogPath` (telemetry logging calculation guard).

### 2. Batch Orchestrator (`src/_MASTER_WHISPER.ps1`)
* `Get-MissingMdFiles`: Updated to test notes and summary markdown presence via `Test-Path -LiteralPath $notesPath` and `Test-Path -LiteralPath $summaryPath`.
* Batch dependency checks:
  - `Test-Path -LiteralPath $CheckPath` and `Get-Content -LiteralPath $CheckPath` when assessing existing processed transcript files.
  - `Test-Path -LiteralPath $OriginalPath` and `Get-Item -LiteralPath $OriginalPath` when resolving parent media from intermediate processed items.
  - `Test-Path -LiteralPath $CurrentFilePath` and `Get-Content -LiteralPath $CurrentFilePath` when verifying non-MD transcript integrity and emptiness.
  - `Test-Path -LiteralPath "$($File.DirectoryName)\$($File.BaseName)$ext"` in missing file reporting.

### 3. Automated Pester Test Suite (`tests/_MASTER_WHISPER.Tests.ps1`)
Added regression tests to `tests/_MASTER_WHISPER.Tests.ps1` in the `Missing Markdown Files Detection` context:
* Dynamically constructs temporary file paths containing literal brackets: `recording [DQ] [PD] Meet`.
* Validates that `Get-MissingMdFiles` correctly returns `both` when files are absent and transitions to `summary` when `.NOTES.md` is created with literal brackets.

---

## Consequences

### Positive
* **Total Filename Resilience**: Files and folders with `[DQ]`, `[PD]`, version tags, brackets, or other special characters are processed without unexpected path resolution failures.
* **Preservation of User Naming**: Users can drop files directly into processing folders without needing to sanitize or rename brackets.
* **Deterministic Logging & Intermediate Handling**: FFmpeg logs and intermediate audio files are accurately verified and moved without false positive warnings.

### Neutral / Operational Considerations
* In all future PowerShell code contributions across `src/`, developers and AI agents must strictly use `-LiteralPath` rather than positional `-Path` whenever interacting with file paths that could potentially contain wildcard characters.
