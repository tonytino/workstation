# workstation

Personal macOS workstation setup, managed by [chezmoi](https://chezmoi.io).
One command on a fresh Mac brings it to a working development state.

## Bootstrap a new Mac

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tonytino/workstation/main/bootstrap.sh)"
```

The script is idempotent — re-running it on an already-configured machine is
safe.

## What it does

Eleven stages, each a separate helper script under `scripts/`:

1. Pre-flight checks (assert macOS, cache sudo).
2. Install Homebrew (official installer).
3. Install the 1Password app + `op` CLI; pause for manual sign-in and CLI
   integration.
4. Install chezmoi.
5. `chezmoi apply` — renders every template under `home/` into `$HOME`. Any
   value that comes from 1Password is read at apply time via `op`.
6. `brew bundle` against `macos/Brewfile` — CLIs, fonts, casks.
7. `macos/defaults.sh` — curated, reversible `defaults write` commands.
8. Generate an ed25519 SSH key (interactive passphrase), add it to ssh-agent
   + Apple Keychain, register the public key with GitHub via `gh`.
9. `gh auth login` if not already authenticated.
10. Install Claude Code (official installer); user runs `/login`
    interactively.
11. Print a manual follow-up checklist.

## Security model

- **No secrets in the repo, ever.** Templates reference 1Password items by
  name (e.g. `op://Personal/Git Identity/email`); the actual values land on
  disk only in the rendered private files in `$HOME`.
- Anything `op` cannot supply is `read -p`-prompted at apply time.
- Private SSH keys are generated locally and never committed in any form
  (encrypted or otherwise). Only the public key is sent to GitHub.
- `scripts/pre-commit-secret-scan.sh` runs `gitleaks` on every commit.
  CI (`.github/workflows/secret-scan.yml`) runs the same check on pushes
  and PRs. Both block on findings.
- No third-party CLIs are added for marginal convenience. App Store apps
  (e.g. Magnet) are listed as manual follow-ups rather than automated via a
  third-party wrapper.

## Layout

```
workstation/
├── bootstrap.sh                     # entry point
├── .chezmoiroot                     # points chezmoi at home/
├── home/                            # everything that lands in $HOME
│   ├── dot_zshrc
│   ├── dot_zprofile
│   ├── dot_gitconfig.tmpl
│   ├── dot_gitignore_global
│   ├── private_dot_ssh/config.tmpl
│   ├── dot_config/
│   │   ├── ghostty/config
│   │   └── nvim/                    # minimal lazy.nvim config
│   └── dot_claude/
│       ├── CLAUDE.md
│       └── settings.json.tmpl
├── macos/
│   ├── Brewfile
│   └── defaults.sh
├── scripts/
│   ├── install-homebrew.sh
│   ├── install-1password.sh
│   ├── install-chezmoi.sh
│   ├── provision-ssh.sh
│   ├── install-claude-code.sh
│   └── pre-commit-secret-scan.sh
└── .github/workflows/
    ├── shellcheck.yml               # bash lint
    └── secret-scan.yml              # gitleaks
```

chezmoi prefix conventions used:
- `dot_` — renders to a leading `.`
- `private_` — sets file mode `0600`
- `executable_` — sets the executable bit
- `.tmpl` — Go-template rendered at apply time

## Day-to-day use

Edit the source files in this repo (or in `~/.local/share/chezmoi/`),
then apply:

```sh
chezmoi diff      # preview what would change in $HOME
chezmoi apply     # apply changes
chezmoi status    # show drift between source and $HOME
```

When you change something in `$HOME` directly and want to capture it:

```sh
chezmoi re-add <path>
```

## License

MIT — see [LICENSE](./LICENSE).

