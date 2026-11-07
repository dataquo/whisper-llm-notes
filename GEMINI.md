# Antigravity Project Rules: WHISPER

## 🚫 Git Operations & Version Control Policy
* **NO AUTOMATIC COMMITS OR PUSHES**: The AI agent must **NEVER** run `git commit`, `git push`, `git tag`, `git merge`, or `git reset` commands.
* **MANUAL HUMAN CONTROL**: All staging, committing, and pushing must be performed manually by the user via GitHub Desktop.
* **READ-ONLY GIT PERMITTED**: The agent is only permitted to run read-only inspection commands (such as `git status` or `git diff`) when helpful for context.
* **COMMIT SUMMARY & DESCRIPTION ON REQUEST ONLY**: The AI agent must generate a formatted **Commit Summary** (subject line) and **Commit Description** (body) for GitHub Desktop **ONLY when explicitly requested by the user**. Do NOT include commit messages automatically after every change.

## 🏛️ Architectural Decoupling & Single Source of Truth
* **Single Source of Truth**: All PowerShell code lives exclusively in `src/`. Never create duplicate scripts in the root directory.
* **Orchestrator Separation**: `src/_MASTER_WHISPER.ps1` is **ONLY** a batch orchestrator (folder scanning, parameter parsing, output checking). NEVER put Docker lifecycle, container management, FFmpeg DSP, or config loading into `_MASTER_WHISPER.ps1`.
* **Execution Engine**: `src/whisper-asr-service-docker.ps1` is the self-contained execution engine handling single files, configuration layering, container lifecycle, FFmpeg DSP, WhisperX ASR, and LLM summarization.

## ⚙️ Configuration Layering & Deterministic Lifecycle
* **No Guessing**: Never write heuristic fallback guessing loops for container names or ports.
* **Layered Config**: Base defaults live in `config/config.default.json` (tracked in Git); machine overrides live in `config/config.local.json` (gitignored). `Get-PipelineConfig` deep-merges them so partial overrides never erase baseline settings.
* **Deterministic Restarts**: Container lifecycle (`Ensure-WhisperContainerRunning`, `Restart-WhisperContainer`) strictly uses `$AppConfig.whisper_service.docker_container_name` and polls `/docs` or `/health` for readiness.

## 📊 Runtime Telemetry & Container Metadata Auditing
* **Explicit Version Logging**: Maintain split `"script_name"` and `"script_version"` (`v06.04`) in all `.log` outputs; never revert to unversioned filename fallback.
* **Resilient Container Metadata**: `Get-WhisperContainerMetadata` must forward `$PipelineConfig` and use multi-tier inspection (Docker inspect $\to$ candidate scan fallback $\to$ HTTP `/openapi.json`) to guarantee zero-null telemetry logs.

## 📁 Filesystem & Special Character Invariants
* **Strict `-LiteralPath` Standard**: Always use `-LiteralPath` on all file provider cmdlets (`Test-Path`, `Get-Content`, `Move-Item`, `Get-Item`, `Remove-Item`) so brackets `[ ]` and capture tags in media filenames (e.g. `[DQ] [PD] Meet...`) are never mishandled as PowerShell wildcard patterns (ADR 0012).


