# Bootstrap flow

`bootstrap.sh` is an idempotent installer that takes a fresh macOS to a working development state. Stage numbering is automatic — `banner()` increments a counter and the total is derived by counting `banner` calls, so stages can be added, removed, or reordered without renumbering.

## Current stages

1. **Pre-flight** — sudo cache + macOS check.
2. **Homebrew** — install if missing.
3. **1Password app + CLI** — installs both, then pauses for the user to sign in to the desktop app and enable CLI integration. `op whoami` must succeed before continuing.
4. **chezmoi** — install via brew.
5. **chezmoi apply** — renders templates from `home/` (per `.chezmoiroot`) into `$HOME`. Templates that reference `op://...` will fail if the 1Password stage didn't authenticate.
6. **Brewfile** — `brew bundle` against `macos/Brewfile`.
7. **macOS defaults** — `macos/defaults.sh`, all curated and reversible.
8. **GitHub auth** — `gh auth login` (or `gh auth refresh`) with `admin:public_key` scope so the next stage can register the SSH key.
9. **SSH key + GitHub registration** — generate ed25519 (interactive passphrase prompt), add to ssh-agent + Apple Keychain, register the public key with GitHub.
10. **Claude Code** — install via Anthropic's official installer.
11. **Claude memory** — clone the private `claude-memory` repo into `~/.claude/projects/<encoded-cwd>/memory` (via `scripts/clone-claude-memory.sh`). Idempotent: pulls if already cloned, refuses to clobber a non-git memory dir.
12. **Pre-commit secret-scan hook** — symlink `scripts/pre-commit-secret-scan.sh` into the clone's `.git/hooks/pre-commit` so local commits are gitleaks-scanned. Idempotent; leaves a pre-existing non-symlink hook alone.
13. **Manual follow-ups checklist** — print remaining human-click items.

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
