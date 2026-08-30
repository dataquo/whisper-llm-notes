# ADR 0006: Strict Manual Git Control Policy for AI Agents

## Status
Accepted

## Context
AI coding assistants (such as Antigravity / Gemini) have terminal execution capabilities. If an agent executes `git commit` or `git push` automatically without prior human inspection:
1. Unreviewed changes, debug artifacts, or temporary files could be prematurely committed.
2. Commit messages might lack user intent or context.
3. Premature pushes could trigger live CI/CD deployments before the user verifies results locally.

## Decision
1. **Explicit AI Constraint**:
   * The AI agent is strictly forbidden from running modifying Git commands:
     - `git commit`
     - `git push`
     - `git tag`
     - `git merge` / `git rebase` / `git reset`
2. **Permanent Rule Enforcement**:
   * Defined in [GEMINI.md](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/GEMINI.md) at the workspace root and documented in [AGENTS.md](file:///d:/_DOCUMENTS/_SCRIPTS/WHISPER/AGENTS.md).
   * Antigravity automatically mounts and enforces this rule on every turn.
3. **Manual Human Staging & Push**:
   * The developer reviews all working tree diffs and commits/pushes manually using **GitHub Desktop**.

## Consequences
### Positive
* Absolute control: 100% of commits and pushes are verified by human eyes before entering version control.
* Clean Git graph: Prevents micro-commit noise and unintended force pushes.
* Safety: Avoids unintended CI/CD runs on work-in-progress code.
