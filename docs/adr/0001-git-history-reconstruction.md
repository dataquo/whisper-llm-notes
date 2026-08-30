# ADR 0001: Historical Git Commit Reconstruction from File Snapshots

## Status
Accepted

## Context
Prior to using Git for version control, development progress was tracked manually by saving snapshot files in the root folder with version suffixes (e.g. `whisper-asr-service-docker.v01.00.ps1` through `v05.06.ps1`, `_MASTER_WHISPER.v04.ps1`, plus experimental `-bad.ps1` variants).

This created several challenges:
1. Directory clutter with 27 snapshot files.
2. Fragile script coupling where batch orchestrators hardcoded specific version filenames (e.g., invoking `.v05.06.ps1`).
3. Inability to use standard Git diffing, tagging, and branch comparisons across historical versions.

## Decision
Instead of creating a single initial commit of the latest version and archiving or discarding past files, we implemented an **automated history reconstruction**:
1. Sequentially committed each file snapshot in chronological order (`v01.00` $\rightarrow$ `v05.06`).
2. Applied the original author/committer timestamps from file creation metadata.
3. Extracted changelog comments from file headers to generate meaningful commit messages.
4. Applied annotated Git tags (`v01.00`, `v02.00`, ..., `v05.06`, `master-v04.00`, `master-v05.05`) to each release point.
5. Consolidated active code into canonical unversioned files (`_MASTER_WHISPER.ps1` and `whisper-asr-service-docker.ps1`).

## Consequences
### Positive
* Full repository timeline (28 commits) is preserved and searchable via `git log`, `git blame`, and GitHub commit history.
* Any past version can be checked out or compared directly (`git diff v01.00 v05.06`).
* File clutter in the working tree is eliminated.

### Negative / Trade-offs
* Initial force push (`git push -u origin main --force`) was required to reconcile the locally generated root history with the remote placeholder repository.
