# ADR 0005: CI/CD Pipeline Architecture & Pester 5 Testing Framework

## Status
Accepted

## Context
As the PowerShell codebase grew into a multi-format orchestrator with regex parsers, timecode formatting, and external API connectors, regressions could be introduced during refactoring without an automated verification system.

## Decision
1. **Automated Continuous Integration (`.github/workflows/ci.yml`)**:
   * Runs on every push and pull request against the `main` branch.
   * **Job 1 (Linting)**: Executes `PSScriptAnalyzer` against `src/` to enforce coding standards, eliminate syntax errors, and detect security issues.
   * **Job 2 (Testing)**: Executes automated unit tests using **Pester 5.5.0** across `tests/`.
2. **Automated Release Pipeline (`.github/workflows/release.yml`)**:
   * Triggers automatically when a version tag (`v*`) is pushed to GitHub.
   * Creates a GitHub Release with auto-generated release notes.
3. **Pester 5 Test Design**:
   * Tests are mock-isolated (do not require running Docker or live Ollama servers).
   * Functions are injected into the global scope to ensure full compatibility with Pester 5's two-phase discovery and execution engine.
   * Standard Pester 5 hyphenated assertions are enforced (`Should -Be`, `Should -BeTrue`, etc.).

## Consequences
### Positive
* Zero broken builds: Any syntax error or regex regression is caught before merging.
* Fast feedback: Full test suite runs in under 2 seconds locally and ~20 seconds in GitHub Actions.
* Automated release packaging: Tagging `v5.7.0` generates official GitHub releases effortlessly.
