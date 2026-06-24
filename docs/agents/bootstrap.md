# Bootstrap flow

`bootstrap.sh` is an idempotent installer that takes a fresh macOS to a working development state. Stage numbering is automatic — `banner()` increments a counter and the total is derived by counting `banner` calls, so stages can be added, removed, or reordered without renumbering.

## Current stages

1. **Pre-flight** — sudo cache + macOS check.
2. **Homebrew** — install if missing.
3. **1Password app + CLI** — installs both, then pauses for the user to sign in to the desktop app and enable CLI integration. `op whoami` must succeed before continuing.
4. **chezmoi** — install via brew.
5. **Git identity + chezmoi init** — resolve the Git identity in shell (1Password vault, name, email), with a graceful fallback: read each value from 1Password (`op read`), falling back to an interactive `/dev/tty` prompt when `op` can't supply it. The values are exported as `WS_OP_VAULT`/`WS_GIT_NAME`/`WS_GIT_EMAIL`, then a single `chezmoi init --source=...` evaluates `home/.chezmoi.toml.tmpl` once and persists them into chezmoi `[data]`. Resolving identity in shell (not via `onepasswordRead` in a file template) means a missing/locked/misnamed vault can't abort the render; persisting via one `init` means the next stage's guarded `status`/`apply` reuse the data without re-prompting.
6. **chezmoi apply** — renders templates from `home/` (per `.chezmoiroot`) into `$HOME` via `scripts/chezmoi-apply-guarded.sh` (never a bare `chezmoi apply`). The Git identity comes from the persisted `[data]` (stage 5), so no vault prompt appears here. Purely additive changes apply silently; any change that would overwrite or delete a pre-existing file prompts per-file (skip / overwrite / backup-then-overwrite / diff). When the conflicting file has a machine-local sidecar (e.g. `~/.zshrc.local`, `~/.gitconfig.local`, `~/.ssh/config.local`, `~/.claude/CLAUDE.local.md`), the prompt prints a tip on how to preserve the current content before overwriting. With no TTY it defaults every conflict to skip rather than clobber. Skipped paths are recorded in `SKIPPED_FILE` and listed in the final checklist with the command to adopt them later. (`--source` is passed explicitly because `chezmoi init` does not persist the source dir.)
7. **Brewfile** — `brew bundle` against `macos/Brewfile`.
8. **macOS defaults** — `macos/defaults.sh`, all curated and reversible.
9. **GitHub auth** — `gh auth login` (or `gh auth refresh`) with `admin:public_key` scope so the next stage can register the SSH key.
10. **SSH key + GitHub registration** — generate ed25519 (interactive passphrase prompt), add to ssh-agent + Apple Keychain, register the public key with GitHub. Reuses the `WS_GIT_EMAIL` resolved in stage 5 as the key comment (falling back to `op` then a prompt).
11. **Claude Code** — install via Anthropic's official installer.
12. **Claude memory** — clone the private `claude-memory` repo into `~/.claude/projects/<encoded-cwd>/memory` (via `scripts/clone-claude-memory.sh`). Idempotent: pulls if already cloned. Probes the remote first and, if it's unreachable (SSH not set up yet, or no access) or a non-git memory dir is in the way, skips gracefully with a recorded follow-up instead of aborting the run. Skipped stages are surfaced in the final checklist.
13. **Pre-commit secret-scan hook** — symlink `scripts/pre-commit-secret-scan.sh` into the clone's `.git/hooks/pre-commit` so local commits are gitleaks-scanned. Idempotent; leaves a pre-existing non-symlink hook alone.
14. **Manual follow-ups checklist** — print remaining human-click items.

## Adding a new stage

1. Write a helper script under `scripts/<verb>-<thing>.sh`. Make it idempotent: detect already-applied state, print a status line, and exit 0.
2. `chmod +x scripts/<your-script>.sh`.
3. Add a `banner "Label"` line + `bash "${SCRIPTS}/your-script.sh"` invocation at the right ordering point in `bootstrap.sh`. No numbers — `banner()` numbers stages automatically.
4. If the stage produces a manual follow-up, append a bullet to the final checklist heredoc in `bootstrap.sh`.
5. Update this stage list and the README's stage list.

## Idempotency rules (mandatory)

Every helper script must be safe to re-run:
- Check before doing. If the thing is already installed/applied, print a confirmation line and `exit 0`.
- Never delete user data without an explicit `read -p` confirmation.
- Use `mktemp` for any temp files; clean them up via `trap '... EXIT'`.
- Pin third-party install URLs to official sources; HTTPS only; document any unpinned URLs in a comment.
