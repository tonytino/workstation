# Global Claude Code Instructions

These rules apply to every Claude Code session on this machine.

## Code style
- Prefer JSDoc for code comments.
- Prefer minimal mocking.

## Tooling
- Prefer CLIs over MCPs. Context7 MCP is acceptable as a fallback when no CLI exists.
- No third-party CLIs unless we own them.

## Security
- Never embed secrets, API keys, or tokens in source-controlled files. Prompt interactively or fetch via the 1Password CLI (`op`) at apply time.
- The 1Password CLI is **read-only**. Only `op read`, `op item get`, `op item list`, `op vault list`, `op whoami`, etc. Never call any create/edit/delete variant. When a new 1Password item needs to exist, tell the user what to create and wait for them to do it.

## Documentation conventions
- Use progressive disclosure for agent-facing project docs:
  - Top-level `CLAUDE.md` (or `README.md` if no separate agent doc exists) holds only critical, always-applicable rules plus a table of contents.
  - Detailed, task-specific guidance lives under `<project-root>/docs/agents/<topic>.md`. One file per topic.
  - The TOC is a 3-column markdown table: `| Topic | Purpose | Load when |`. Each row links to a doc with both a description and a trigger condition.
  - The trigger condition lives in the TOC only — don't duplicate it inside each detailed doc.

## Repository conventions
- This machine's dotfiles are managed by chezmoi from https://github.com/tonytino/workstation. Edit source files in `~/.local/share/chezmoi/` (or the cloned repo) and run `chezmoi apply`, not the rendered files in `$HOME` directly.

## Machine-local overrides

Machine-specific rules live in `~/.claude/CLAUDE.local.md` (not managed by
chezmoi). It is imported below so both this file and the local one are in
effect. The file is optional — create it by hand per machine.

@~/.claude/CLAUDE.local.md
