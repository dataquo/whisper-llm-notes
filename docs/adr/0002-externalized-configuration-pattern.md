# ADR 0002: Externalized Hierarchical Configuration Pattern

## Status
Accepted

## Context
Script parameters, API server endpoints (WhisperX on port 9000, Ollama on port 11434, LM Studio on remote/local port 1234), and FFmpeg audio normalization filter chains were originally hardcoded directly into PowerShell variables.

This made it difficult to:
1. Change models or network IP addresses without editing core script logic.
2. Run across different developer environments (e.g. laptop vs GPU server) without creating Git diffs.
3. Keep custom network IPs and private endpoints clean from public repository commits.

## Decision
Adopt a 2-tier JSON configuration system:
1. **`config/config.default.json`**: Checked into Git. Contains default production settings, standard filter chains (`phone`, `meeting`, `distant`), and standard model names.
2. **`config/config.local.json`**: Git-ignored (`.gitignore`). Automatically loaded if present to override any setting (e.g. custom LAN IP addresses for LM Studio or custom Ollama models).
3. Scripts accept an optional `-ConfigPath` parameter and fall back to scanning standard relative locations (`..\config\config.default.json`, `config\config.default.json`).

## Consequences
### Positive
* Environment isolation: Scripts can run on any host by supplying a local JSON configuration.
* Safe commits: Changes to local IP addresses or hardware setups never dirty Git history.
* Fallback resilience: Core scripts retain sensible internal defaults if JSON configuration is unavailable.
