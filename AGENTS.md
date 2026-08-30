# AGENTS.md - AI Agent Operating Context & Instructions

This document provides system context, architectural guidelines, testing commands, and operational constraints for AI coding agents (such as Antigravity, Gemini, Claude, and Copilot) working in the **WHISPER** repository.

---

## 1. Project Purpose & Architecture

WHISPER is a resilient, batch audio transcription and AI summarization pipeline. It combines:
1. **PowerShell 7+** for orchestrating pipelines and manipulating file formats in RAM.
2. **FFmpeg** for profile-based digital signal processing (DSP) and broadcast loudness normalization (-16 LUFS).
3. **WhisperX (Docker)** on port 9000 for ASR, word timestamps, and multi-speaker diarization.
4. **LM Studio** on port 1234 / remote for detailed structured meeting notes (`.NOTES.md`).
5. **Ollama** on port 11434 for executive summaries (`.SUMMARY.md`).

---

## 2. Directory Layout & Key Files

```text
WHISPER/
├── src/
│   ├── _MASTER_WHISPER.ps1        # Batch orchestrator: scans folders, detects missing outputs
│   └── whisper-asr-service-docker.ps1 # Engine: FFmpeg DSP -> WhisperX -> Multi-format -> LLM
├── config/
│   ├── config.default.json        # Tracked base settings, filter chains, and default models
│   └── config.local.json.example  # Untracked local override template
├── tests/
│   ├── _MASTER_WHISPER.Tests.ps1  # Unit tests for parameter extraction & checks
│   └── whisper-asr-service-docker.Tests.ps1 # Unit tests for timecodes & format converters
├── docs/
│   ├── ARCHITECTURE.md          # End-to-end technical architecture & diagrams
│   ├── WORKFLOW_GUIDE.md        # Operations & troubleshooting guide
│   └── adr/                     # Architectural Decision Records (0001-0006)
├── .github/workflows/
│   ├── ci.yml                   # PSScriptAnalyzer + Pester 5 CI pipeline
│   └── release.yml              # Automated release packaging on tag push
├── CHANGELOG.md                 # Full release history from v01.00 to current
├── GEMINI.md                    # Active rules (NO automatic git commits/pushes)
└── README.md                    # Project overview & quickstart
```

---

## 3. Strict Operating Rules for AI Agents

> [!CAUTION]
> **Git Operations Policy (Human-in-the-Loop)**
> * The AI agent must **NEVER** run `git commit`, `git push`, `git tag`, `git merge`, or `git reset`.
> * All staging, committing, and pushing must be performed manually by the human user via **GitHub Desktop**.
> * The AI agent is only permitted to run read-only inspection commands (`git status`, `git diff`) when needed for context.
> * **Mandatory Output Requirement**: At the end of every change, the AI agent must always generate a ready-to-copy **Commit Summary** (title) and **Commit Description** (body) formatted specifically for GitHub Desktop.

---

## 4. Coding & Quality Standards

1. **Encoding**: All file writes containing text or transcript content must use clean UTF-8 without BOM:
   ```powershell
   $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
   [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
   ```
2. **Pester Unit Tests**:
   * All new functions or parameter changes must include unit tests in `tests/`.
   * Use Pester 5 standard hyphenated assertions: `Should -Be`, `Should -BeTrue`, `Should -BeFalse`, `Should -BeNullOrEmpty`, `Should -Match`.
   * In `BeforeAll`, register helper functions into the global scope (`function global:FunctionName`) so they are accessible to Pester 5 test blocks.
3. **PSScriptAnalyzer**:
   * Ensure changes pass `Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1` with zero Errors.

---

## 5. Verification Commands

Before concluding any refactoring or feature implementation, run the test suite:
```powershell
# Run Pester Unit Tests
Invoke-Pester -Path ./tests -Output Detailed

# Run PowerShell Linter
Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

---

## 6. How to Add New Audio Profiles

1. Add profile settings to [config/config.default.json](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/config/config.default.json) under `"profiles"`.
2. Update the FFmpeg filter chain in [src/whisper-asr-service-docker.ps1](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/src/whisper-asr-service-docker.ps1).
3. Add a corresponding test case in [tests/_MASTER_WHISPER.Tests.ps1](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/tests/_MASTER_WHISPER.Tests.ps1).
4. Update documentation in [docs/ARCHITECTURE.md](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/docs/ARCHITECTURE.md).
