# Workstation — Agent Instructions

These are the rules an agent must follow to safely contribute to this repo.
Detailed guidance lives under `docs/agents/`; load only what your task needs.

## Critical rules

- **No secrets in the repo, ever.** Use `op://...` references in chezmoi templates or `read -p` interactive prompts in helper scripts. Never inline a key, token, or password — even commented-out.
- **1Password CLI is read-only.** Only `op read`/`op * get`/`op * list`. Never `op item create`, `op item edit`, `op item delete`, or any other write/mutate command. To add a new 1Password item, tell the user the vault, item name, and field names and wait for them to create it.
- **No third-party CLIs unless we own them.**
- **Every shell script uses `set -euo pipefail` and is idempotent.** Re-running on a configured machine must be safe and a no-op where appropriate.
- **Lint before pushing.** `gitleaks protect --staged` and ShellCheck must pass. CI runs both on every push and PR.
- **Author identity for commits is `tonytino <10490190+tonytino@users.noreply.github.com>`.** This repo is public. Always use the noreply identity — no personal email in git history.

## Detailed docs

| Topic | Purpose | Load when |
|---|---|---|
| [bootstrap](docs/agents/bootstrap.md) | bootstrap.sh stage layout and how to add or reorder one | editing the install flow or any helper script under `scripts/` |
| [secrets](docs/agents/secrets.md) | 1Password references and interactive-prompt patterns | adding any step that needs a credential, key, or other sensitive value |
| [chezmoi](docs/agents/chezmoi.md) | source-tree prefix conventions and template patterns under `home/` | adding, removing, or templating any file under `home/` |
