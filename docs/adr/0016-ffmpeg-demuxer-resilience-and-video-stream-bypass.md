# ADR 0016: FFmpeg Demuxer Resilience, Video Stream Bypass (-vn), and Truncated Cutfile Recovery

## Status
Accepted (v07.01)

## Context
In the WHISPER batch transcription pipeline, media input files frequently originate from meeting platforms (Zoom, Teams, Google Meet), webinar archives, and video clipping software (designated with `.cutfile.` naming conventions). These files are often high-resolution videos (1080p, 1440p/2K, 4K) where only the audio stream is required for downstream WhisperX ASR and PyAnnote diarization.

During production runs on both macOS and Windows, two interconnected operational issues were identified:

### 1. Truncated Audio Streams and Demuxer EOF Stalls
When processing `.cutfile.` media or files read from external storage / network volumes (`/Volumes/_VIDEO` on macOS), FFmpeg frequently encountered corrupted packets at the tail end of recordings:
```text
[mov,mp4,m4a,3gp,3g2,mj2 @ 0xca2c20000] Packet corrupt (stream = 0, dts = 136675328).
[in#0/mov,mp4,m4a,3gp,3g2,mj2 @ 0xca2c1c000] corrupt input packet in stream 0
[mov,mp4,m4a,3gp,3g2,mj2 @ 0xca2c20000] stream 0, offset 0xc7975b1: partial file
[aac @ 0xca2c29500] decode_band_types: Input buffer exhausted before END element found
[in#0/mov,mp4,m4a,3gp,3g2,mj2 @ 0xca2c1c000] Error during demuxing: Input/output error
```
At the point of truncation (e.g. at 47m 21s), FFmpeg stalled for over 90 seconds attempting to parse the invalid container boundary before finally flushing the output file, significantly delaying batch execution.

### 2. Low Hardware Utilization & Conversion Throughput Discrepancies
Users observed low overall CPU utilization (6%–8%) and 0% GPU utilization during the FFmpeg audio extraction stage, with throughput hovering at ~6x–8x real-time speed on long files:
* **Why GPU is Idle**: GPUs (CUDA / Apple Metal) accelerate video codecs and neural network tensor operations. Audio digital signal processing (DSP) filters (`dynaudnorm`, `speechnorm`, `loudnorm`) and MP3 encoding (`libmp3lame`) execute exclusively on the CPU.
* **Single-Thread Bottleneck**: Audio filtergraphs and the LAME MP3 encoder operate sequentially on a single CPU core. On 12-core to 24-core CPUs, one saturated thread appears as low overall system utilization.
* **Cumulative Speed Curve**: FFmpeg's `speed=` indicator represents the cumulative average ($\text{processed audio time} / \text{elapsed wall clock time}$). Conversions typically start at 25x–30x while reading from the operating system's RAM page cache, then drop to ~7x as physical disk I/O, USB bus contention on external volumes, or EOF parsing stalls accumulate.
* **Unnecessary Video Stream Parsing**: Because `-vn` (disable video) was previously omitted, FFmpeg's container demuxer parsed every video packet from the container (gigabytes of 1080p/2K video) merely to discard them at the output stage.

---

## Decision & Evaluation of Alternatives

### Alternative 1: Switch Default Audio Format to Uncompressed WAV (`pcm_s16le`)
* *Mechanism*: Replace `libmp3lame` encoding with uncompressed 16-bit PCM WAV.
* *Analysis*: Completely eliminates CPU encoding overhead (yielding ~30%–50% faster preprocessing). However, uncompressed WAV files are ~4x larger than 64 kbps MP3 files.
* *Verdict*: **Rejected**. Preserving MP3 format compatibility across storage archives and existing pipeline telemetry remains an architectural priority.

### Alternative 2: Simplify or Remove `loudnorm` (EBU R128) Filter
* *Mechanism*: Remove the EBU R128 loudness normalization filter to reduce single-threaded CPU processing time.
* *Analysis*: `loudnorm` performs internal 192 kHz true-peak oversampling. While removing it increases throughput, doing so violates the pipeline's core invariant of uniform -16 LUFS loudness normalization across all audio profiles (`meeting`, `phone`, `distant`, `hallway`, `echoed`).
* *Verdict*: **Rejected**. Audio DSP profiles exist for acoustic stability and Whisper ASR accuracy.

### Selected Strategy: Demuxer Resilience Flags & Video Stream Bypass (`-vn`)

We adopted targeted input and demuxing optimizations within `src/whisper-asr-service-docker.ps1`:
```powershell
$FfMpegCmd = "$ffmpegBin -err_detect ignore_err -fflags +genpts+igndts+discardcorrupt -i `"$FilePath`" -vn -af `"$ffmpegFilter`" $FfMpegOutputParams -ac 1 -ar 16000 `"$TempProcessedFile`" -y"
```

1. **`-vn` (Video Stream Bypass)**:
   * Instructs FFmpeg's demuxer to completely ignore video tracks (`Stream #0:0(und): Video`), avoiding the overhead of parsing gigabytes of high-resolution video frames from the container.
2. **`-err_detect ignore_err`**:
   * Instructs bitstream decoders to ignore non-fatal syntax errors, truncated packets, and missing EOF markers, preventing demuxer abortion.
3. **`-fflags +genpts+igndts+discardcorrupt`**:
   * `discardcorrupt`: Immediately drops corrupted audio packets rather than stalling in retry loops.
   * `genpts`: Regenerates missing presentation timestamps.
   * `igndts`: Ignores non-monotonic decode timestamps, ensuring timestamp continuity for downstream diarization and alignment.

---

## Consequences

### Positive
* **Throughput Multiplier**: Sustained audio conversion speeds increased from **~7.8x** to **22.7x–25x** real-time speed (e.g. converting 14 min 17 sec of 2K video audio in just 37.8 seconds).
* **Zero Tail-End Hangs**: FFmpeg no longer stalls on truncated `.cutfile.` recordings or partial AAC packets at EOF, eliminating 90+ second idle timeouts.
* **Full Profile & Format Invariance**: Retains 100% compatibility with existing DSP filter chains, -16 LUFS broadcast normalization, and 64 kbps MP3 storage efficiency.
* **Cross-Platform Parity**: Applies identically across Windows 11 (`ffmpeg.exe`) and macOS Apple Silicon (`ffmpeg`).

### Negative
* Severely damaged files with missing audio header metadata still require explicit remuxing (`ffmpeg -i input.mp4 -c copy repaired.mp4`) if the container's index atom (`moov`) is entirely absent.
