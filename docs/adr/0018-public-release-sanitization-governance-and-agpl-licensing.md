# ADR 0018: Public Release Sanitization, Repository Governance, and AGPL-3.0 Dual-Licensing

## Status
Accepted (v07.03)

## Context
Originally developed as an internal, private repository (`https://github.com/dataquo/WHISPER`), the project evolved into an enterprise-grade batch audio transcription and structured AI meeting notes pipeline supporting dual hardware execution (Windows CUDA Docker and macOS Apple Silicon MLX). 

To give back to the open-source community, provide a public reference architecture, and allow external adoption while protecting commercial rights, DataQuo decided to transition the repository to **Public** visibility under the project name **`whisper-llm-notes`** (`https://github.com/dataquo/whisper-llm-notes`).

Prior to making the codebase public, several strategic, security, and legal questions required formal evaluation:
1. **Privacy & Security Audit**: Auditing the entire codebase and 42 Git historical commits for hardcoded credentials, personal names, internal usernames, hostnames, IP addresses, and private network directory paths.
2. **Project Identity & Discoverability**: Selecting a clear, search-optimized repository name and metadata tags on GitHub that maximize organic developer discovery without paid marketing.
3. **Open-Source Licensing vs. Commercial Protection**: Selecting an open-source license that freely permits personal, homelab, and academic use, while legally preventing commercial entities from wrapping the pipeline into a paid SaaS service without paying licensing fees or royalties to DataQuo.
4. **macOS Dependency Packaging**: Resolving an unintentional `.gitignore` rule that blocked tracking of `macos/requirements-macos.txt`.

---

## Decision

### 1. Privacy Sanitization & Invariants
* **Git History Verification**: Confirmed that all 42 historical commits were cleanly authored by `dataquo <ceo@dataquo.eu>`, with zero personal email addresses, personal names, or exposed Hugging Face/OpenAI tokens across all commit diffs.
* **Storage Topology Neutralization**: Replaced internal network share paths (`\\truenas\_DOWNLOADS\_TEMP\...`) with generic mock paths (`\\server\share\recordings\...`) in test suites ([tests/whisper-asr-service-docker.Tests.ps1](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/tests/whisper-asr-service-docker.Tests.ps1)) and script comments.
* **macOS Dependency Tracking**: Added exception `!macos/requirements*.txt` to [.gitignore](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/.gitignore) so `macos/requirements-macos.txt` is fully tracked in Git.
* **Template Consolidation**: Removed redundant duplicate `macos/env.example`, establishing `macos/.env.example` as the canonical template.

### 2. Project Naming: `whisper-llm-notes`
Evaluated multiple naming archetypes:
* *Option A (Brandable)*: `whisper-scribe` — memorable but lower organic search intent.
* *Option B (Pipeline-centric)*: `whisper-notes-pipeline` — accurate, but less search volume.
* *Option C (Search-Optimized - Selected)*: **`whisper-llm-notes`** — perfectly matches high-intent developer searches combining Whisper ASR and local LLM summarization.
* Configured 15 GitHub discovery topic tags: `whisper`, `whisperx`, `meeting-notes`, `speech-to-text`, `transcription`, `speaker-diarization`, `mlx`, `apple-silicon`, `metal-gpu`, `ffmpeg`, `ollama`, `lm-studio`, `powershell`, `local-ai`, `pyannote`.

### 3. Licensing Decision: GNU AGPLv3 Dual-Licensing Model
We evaluated four open-source and source-available licensing models:

| License Model | Community Adoption | Cloud/SaaS Freeloading Protection | Commercial Monetization Fit | Evaluation |
| :--- | :--- | :--- | :--- | :--- |
| **MIT** | Maximum | None ($0 cut) | None (anyone can resell) | Rejected. Allows competitors to commercialize without payment. |
| **Apache 2.0** | Maximum | None ($0 cut) | Brand/Consulting only | Rejected. Provides patent defense, but competitors can still sell hosted service for free. |
| **BSL 1.1 (Business Source License)** | Moderate | High (explicit fee) | Strong, but non-OSI | Rejected for launch. Creates skepticism among open-source developers; excluded from curated Awesome lists. |
| **GNU AGPL-3.0** | High | **High (Copyleft)** | **Dual-Licensing Standard** | **Accepted.** Recognized as true open source while obligating SaaS providers to buy a commercial license. |

#### Why AGPL-3.0 Fits DataQuo's Strategic Objectives:
1. **Freedom for Individuals & Developers**: Free to inspect, fork, modify, and run locally on Windows and Mac.
2. **The "Affero" SaaS Trigger**: Section 13 mandates that if any entity runs a modified or integrated version of this software over a computer network (e.g. providing a commercial transcription/meeting notes SaaS), they must make the entire backend source code available under AGPL-3.0.
3. **Dual-Licensing Revenue**: Because commercial SaaS startups refuse to open-source their proprietary application stacks, their only legal avenue is to negotiate a **Commercial / Enterprise License** from **DataQuo** (the sole copyright holder).
4. **Future Relicensing Rights**: Because DataQuo owns 100% of the copyright for all authored code, DataQuo retains the unilateral legal right to relicense future releases under alternative terms (e.g., BSL or commercial) at any time.

---

## Consequences

### Positive
* **Safe Public Footprint**: Repository contains zero proprietary LAN infrastructure secrets or unreleased internal directory topologies.
* **Maximized Discoverability**: Named and tagged for immediate ranking across GitHub explore pages and developer search queries.
* **Commercial Protection**: SaaS competitors cannot take the pipeline and sell closed-source cloud services without either open-sourcing their own code or paying license fees to DataQuo.
* **Turnkey macOS Onboarding**: Public users cloning the repository can immediately run `./macos/setup_macos.sh` because `requirements-macos.txt` is now tracked.

### Considerations & Trade-offs
* **Corporate Contributor Caution**: Some strict enterprise legal departments restrict employees from contributing to AGPL-licensed repositories. However, because this is an end-to-end executable pipeline rather than a redistributable library (like a NuGet or pip package), adoption impact is minimal.
* **Pull Request Governance**: All future community contributions must either assign copyright to DataQuo or grant unrestricted dual-licensing rights so DataQuo maintains full authority to issue commercial licenses.
