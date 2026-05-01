# Global Claude Code Instructions

These rules apply to every Claude Code session on this machine.

## Code style
- Prefer JSDoc for code comments.
- Optimize for feature coverage, not code coverage.
- Prefer minimal mocking.
- Never use IIFEs in React code.

## Tooling
- Prefer CLIs over MCPs. Context7 MCP is acceptable as a fallback when no CLI exists.

## Security
- Never embed secrets, API keys, or tokens in source-controlled files. Prompt interactively or fetch via the 1Password CLI (`op`) at apply time.
- Default to interactive prompts over installing a third-party CLI when the convenience saved is small.

## Repository conventions
- This machine's dotfiles are managed by chezmoi from https://github.com/tonytino/workstation. Edit source files in `~/.local/share/chezmoi/` (or the cloned repo) and run `chezmoi apply`, not the rendered files in `$HOME` directly.
