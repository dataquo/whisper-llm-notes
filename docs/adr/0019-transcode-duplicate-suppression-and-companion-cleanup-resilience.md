# ADR 0019: Transcode Duplicate Suppression, Companion Cleanup Resilience, and ExifTool Log Discrimination

## Status
Accepted (v07.04)

## Context
In automated media ingestion pipelines integrating `src/_MASTER_WHISPER.ps1` with external video transcoding (`..\DJI\convert_DJI_videos_with_MetaData.ps1`) and log management (`..\DJI\LogFolderValidateAndZip.ps1`), three critical edge cases were observed in production environments (e.g., `\\truenas\...` network shares across Windows 11 and macOS Apple Silicon):

1. **Duplicate Transcripts & LLM API Cost Inflation (`006 - Copy`)**:
   When batch folders contained media previously transcribed from original camera captures (e.g., `recording.CS-M2.mp4` with existing `recording.CS-M2.NOTES.md` and `.json`), subsequent runs of `_MASTER_WHISPER.ps1` triggered video transcoding, generating `recording.CS-M2.CRF-44_LIBSVT-AV1_P2_SO_APPLE_M2_3840x2160.webm`. Because the orchestrator checked for missing markdown files strictly matching the full WebM filename, it re-transcribed the entire audio track and generated duplicate notes (`...CRF-44...NOTES.md` alongside `.NOTES.md`), doubling transcription time and LLM token usage.

2. **The Over-Suppression Trap & Batch Pipeline Stalling (`Test12`)**:
   To prevent duplicate WebM processing, an initial naive suppression check excluded any converted WebM if matching media was found anywhere in the folder or in quarantine subfolders (`_TO_DELETE_`, `_ORIGINALS_`). However, in a standard fresh conversion workflow:
   - `convert_DJI_videos_with_MetaData.ps1` transcodes `video.mp4` to `video.CRF-44...webm`.
   - `LogFolderValidateAndZip.ps1` validates the transcode and moves `video.mp4` to `_TO_DELETE_\`.
   - When `_MASTER_WHISPER.ps1` scanned the directory, it observed `video.mp4` in `_TO_DELETE_\`, concluded original media existed, and suppressed the converted WebM.
   - Because `_MASTER_WHISPER.ps1` excludes `_TO_DELETE_\` from media discovery, **zero audio files were processed**, and the recording was never transcribed.

3. **ExifTool Metadata Logs Shielded from ZIP Archiving (`Test15`)**:
   During external video conversion, `exiftool -ExtractEmbedded -a -g1 -w! txt` dumps container metadata into `$baseName.txt` alongside `$baseName.mp4`. Later, `LogFolderValidateAndZip.ps1` archives logs to category ZIPs and purges them from the source folder. However, an overly broad guard intended to protect Whisper ASR `.txt` transcripts checked if `$baseName.mp4` existed in `_TO_DELETE_`. Because every ExifTool dump matched an MP4 moved to `_TO_DELETE_`, all ExifTool `.txt` files were misclassified as Whisper transcripts and left unarchived in the root folder.

---

## Decisions

### 1. Base-Transcript Duplicate Suppression (`src/_MASTER_WHISPER.ps1`)
In `src/_MASTER_WHISPER.ps1`, converted WebM files (`*.CRF-*_LIBSVT-AV1*.webm`) and intermediate preprocessed files are filtered using two decoupled invariants:
1. **Active Folder Original Media Check**:
   A converted WebM is suppressed if matching original media (`.mp4`, `.mov`, `.m4a`, `.flac`, `.mp3`) exists directly in `$_.DirectoryName`.
   Quarantine subfolders (`_TO_DELETE_`, `_ORIGINALS_`) are **excluded** from this check.
2. **Existing Base Transcript Lookup**:
   If the original media was moved to `_TO_DELETE_` or deleted by the user, the orchestrator strips transcode suffixes (`.CRF-44_LIBSVT-AV1...`) to recover `$baseWithoutDjiSuffix` and tests whether non-empty base transcripts (`.json`, `.NOTES.md`, `.SUMMARY.md`, `.srt`, `.tsv`, `.vtt`, `.txt`) already exist in `$_.DirectoryName`.
   - If base transcripts exist: the WebM is suppressed as a duplicate.
   - If no base transcripts exist: the WebM is **retained and queued for transcription**, ensuring fresh conversions in `_TO_DELETE_` workflows are transcribed seamlessly.
3. **Intermediate Processed Audio Guard**:
   Candidate filtering checks intermediate `.mp3` files against `$baseWithoutDjiSuffix` transcripts to prevent re-transcription while preserving the files in storage for user playback and quality audits.

### 2. Fast Content-Header Log Discrimination (`DJI/LogFolderValidateAndZip.ps1`)
In `LogFolderValidateAndZip.ps1`, Phase 2 log archiving distinguishes ExifTool metadata logs from Whisper ASR transcripts without relying on brittle media existence heuristics:
1. **ExifTool Header Fast Inspection**:
   Inspects the initial lines of each `.txt` file via `Get-Content -TotalCount 5`. If the content matches `---- ExifTool ----` or `ExifTool Version Number`, it is unequivocally classified as an ExifTool metadata log. It is archived to the category ZIP and purged from the source directory.
2. **Companion Whisper Format Guard**:
   A `.txt` file is recognized as a genuine Whisper ASR transcript and preserved in the source folder **only** if companion transcript formats (`.json`, `.NOTES.md`, `.SUMMARY.md`, `.srt`, `.vtt`, `.tsv`) exist for the same base name.
3. **Removal of Broad Media Fallback**:
   The legacy fallback checking for `.mp4` files in `_TO_DELETE_` was eliminated, preventing metadata dumps from masquerading as speech transcripts.

### 3. Benign macOS Runtime Diagnostics
Documented benign macOS console warnings observed during cross-platform execution:
* **`MallocStackLogging`**: `MallocStackLogging: can't turn off malloc stack logging because it was not enabled` is an informational diagnostic emitted by macOS `libsystem_malloc.dylib` when child processes or worker threads initialize without `MallocStackLogging` environment variables enabled. It has zero impact on Python or PowerShell execution.
* **`[opus @ ...] Error parsing Opus packet header`**: FFmpeg demuxer probing artifact on WebM Opus streams during demuxer initialization. Stream demuxing recovers immediately without packet loss due to `-err_detect ignore_err -fflags +genpts+igndts+discardcorrupt`.

---

## Consequences & Trade-offs

### Pros
* **Zero Duplicate Transcripts**: Converting folders with existing transcripts no longer incurs double GPU runtime or redundant LLM summarization.
* **Seamless Fresh Ingestion**: Folders where original MP4s are moved to `_TO_DELETE_` during pre-processing transcribe without manual intervention.
* **Complete Folder Tidy-Up**: ExifTool `.txt` dumps are reliably moved to category ZIPs while Whisper `.txt` transcripts remain safely in the source folder alongside `.NOTES.md`.
* **Intermediate Audio Preservation**: Audio files generated during DSP normalization (`.PHONE-NORM...mp3`, `.MEETING-NORM...mp3`) are retained for auditing.

### Cons & Mitigations
* *Single-Format Deletion Edge Case*: If a user manually deletes all companion files (`.json`, `.NOTES.md`, `.srt`, etc.) leaving only a bare `.txt` Whisper transcript that lacks ExifTool headers, running cleanup will treat it as a generic log.  
  *Mitigation*: The Whisper pipeline always generates 5 output formats plus 2 Markdown files simultaneously. Deleting all 6 companions while keeping only `.txt` is an unnatural workflow. Furthermore, genuine transcripts contain dialogue strings (`[SPEAKER_...]:`) distinct from logs.
