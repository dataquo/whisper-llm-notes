# Antigravity Project Rules: WHISPER

## 🚫 Git Operations & Version Control Policy
* **NO AUTOMATIC COMMITS OR PUSHES**: The AI agent must **NEVER** run `git commit`, `git push`, `git tag`, `git merge`, or `git reset` commands.
* **MANUAL HUMAN CONTROL**: All staging, committing, and pushing must be performed manually by the user via GitHub Desktop.
* **READ-ONLY GIT PERMITTED**: The agent is only permitted to run read-only inspection commands (such as `git status` or `git diff`) when helpful for context.
* **ALWAYS PROVIDE COMMIT SUMMARY & DESCRIPTION**: At the end of every response where changes are made, the AI agent must always provide a formatted **Commit Summary** (subject line) and **Commit Description** (body) that the user can directly copy and paste into GitHub Desktop.
