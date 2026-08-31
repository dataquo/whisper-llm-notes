# ADR 0009: Idiomatic Comment-Based Help, Parameter Discovery & Batch UX Strategy

## Status
Accepted (v06.02)

## Context
As the WHISPER transcription pipeline evolved across v06.00 and v06.01, several advanced orchestration capabilities and digital signal processing options were integrated:
1. **Selective Generation Switches**: Flags such as `-OnlyOllama` (generate only `.SUMMARY.md`), `-OnlyLMStudio` (generate only `.NOTES.md`), and `-DisableLLM` (ASR only).
2. **Multiple Parameter Aliases**: Case-insensitive aliases (`-OnlyOlama`, `-OllamaOnly`, `-LMStudioOnly`, `-OnlyLM`, `-DisableLLMs`, `-SkipLLM`, `-NoLLM`) designed for user ergonomics.
3. **Complex Filename Convention**: Automatic extraction of language codes (`CS`, `SK`, `EN`), DSP profiles (`P`, `M`, `D`, `H`, `E`), and speaker counts from filenames formatted as `[name].[LL]-[X][#].[ext]`.

**Problem Statement**:
Users periodically forget supported CLI switches, exact alias names, or the syntax for filename-based parameter tagging (e.g. which profile letter corresponds to echo vs. hallway or how speaker diarization counts are specified). We needed an effective, discoverable, and clean mechanism to provide users with immediate help and hints directly in the CLI.

## Decision & Evaluation of Alternatives

We evaluated three potential UX and help delivery approaches:

### Option A: Automatic Runtime Console Banner Injection
- *Mechanism*: Inject a multi-line ASCII banner or tip box at the start of every script invocation (e.g., printing active modes and tip prompts to `stdout`).
- *Pros*: Completely unmissable; visible every time a user runs the script without requiring extra arguments.
- *Cons*: Pollutes clean stdout in automated cron jobs, CI pipelines, and piped logs; adds unnecessary runtime rendering logic to `_MASTER_WHISPER.ps1`, conflicting with our core invariant rule to keep the orchestrator lightweight.

### Option B: Custom Interactive `-Help` / `-h` Switch
- *Mechanism*: Implement an explicit `[switch]$Help` parameter and write dedicated PowerShell `Write-Host` formatting code to print an in-terminal cheatsheet.
- *Pros*: Allows custom terminal ANSI colors and ASCII formatting without running `Get-Help`.
- *Cons*: Redundant with PowerShell's native engine; does not integrate with PowerShell's standard discovery commands (`Get-Help -Examples`, `Get-Help -Full`, `Get-Command -Syntax`); adds execution branches to the orchestrator.

### Option C: Idiomatic PowerShell Comment-Based Help (CBH) [SELECTED]
- *Mechanism*: Structure the top-level block comment of `src/_MASTER_WHISPER.ps1` using official PowerShell Comment-Based Help keywords: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER <name>`, `.EXAMPLE`, and `.NOTES`.
- *Pros*:
  - **Native Integration**: Seamlessly powers `Get-Help .\src\_MASTER_WHISPER.ps1`, `Get-Help ... -Full`, `Get-Help ... -Examples`, and standard `.\src\_MASTER_WHISPER.ps1 -?`.
  - **IntelliSense & Tab Completion**: Enables PowerShell 7+ autocomplete (<kbd>Tab</kbd> and <kbd>Ctrl</kbd>+<kbd>Space</kbd>) to automatically display parameter documentation and all registered aliases.
  - **Zero Runtime Overhead**: Help is parsed on-demand by PowerShell's help engine rather than executing code during batch runs.
  - **Architectural Purity**: Keeps `_MASTER_WHISPER.ps1` strictly decoupled, lightweight, and free of extraneous presentation code.

## Implementation Details

1. **Detailed Filename Convention Reference in `.DESCRIPTION`**:
   The Comment-Based Help explicitly documents the `[name].[LL]-[X][#].[ext]` regex pattern, breaking down:
   - Language codes (`SK`, `CS`, `EN`, auto-detection).
   - All 5 DSP profiles: `P` (Phone), `M` (Meeting), `D` (Distant), `H` (Hallway), `E` (Echoed).
   - Diarization speaker counts (sets `min_speakers` and `max_speakers`).
   - Default fallbacks for untagged files.
   - Real-world filename examples.

2. **Complete Parameter & Alias Documentation in `.PARAMETER`**:
   Every switch (`-InputFolder`, `-ConfigPath`, `-DisableLLM`, `-OnlyOllama`, `-OnlyLMStudio`) includes full functional descriptions and lists all valid aliases.

3. **Practical Snippets in `.EXAMPLE`**:
   Provides four ready-to-run copy-paste command examples for default runs, selective summaries, and ASR-only workflows.

## Consequences

### Positive
- **Instant Discovery**: Users can run `Get-Help .\src\_MASTER_WHISPER.ps1 -Full` or `.\src\_MASTER_WHISPER.ps1 -?` to see full switch descriptions and filename conventions.
- **Enhanced IntelliSense**: PowerShell tab-completion reveals all parameters and aliases interactively.
- **Architectural Decoupling Preserved**: `src/_MASTER_WHISPER.ps1` remains a pure batch orchestrator without bloated presentation loops.

### Negative
- Users must actively invoke `Get-Help`, `-?`, or tab-completion to see help rather than having it printed unconditionally on every batch run.
