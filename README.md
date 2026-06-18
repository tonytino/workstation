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

Stages run in order (numbering is automatic in `bootstrap.sh`):

1. Pre-flight checks (assert macOS, cache sudo).
2. Install Homebrew (official installer).
3. Install the 1Password app + `op` CLI; pause for manual sign-in and CLI
   integration.
4. Install chezmoi.
5. `chezmoi apply` — renders every template under `home/` into `$HOME`. Any
   value that comes from 1Password is read at apply time via `op`.
6. `brew bundle` against `macos/Brewfile` — CLIs, fonts, casks.
7. `macos/defaults.sh` — curated, reversible `defaults write` commands.
8. `gh auth login` (or `gh auth refresh`) with the `admin:public_key` scope so
   the next stage can register an SSH key.
9. Generate an ed25519 SSH key (interactive passphrase), add it to ssh-agent
   + Apple Keychain, register the public key with GitHub via `gh`.
10. Install Claude Code (official installer); user runs `/login` interactively.
11. Clone the private `claude-memory` repo into the Claude Code memory dir.
12. Symlink the gitleaks pre-commit hook into the clone's `.git/hooks`.
13. Print a manual follow-up checklist.

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
│       └── modify_settings.json     # merge script (see "Machine-local" below)
├── macos/
│   ├── Brewfile
│   └── defaults.sh
├── scripts/
│   ├── install-homebrew.sh
│   ├── install-1password.sh
│   ├── install-chezmoi.sh
│   ├── provision-ssh.sh
│   ├── install-claude-code.sh
│   ├── clone-claude-memory.sh
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
- `modify_` — an executable script that receives the current target file on
  stdin and emits the new contents on stdout (used to merge into files that
  apps rewrite at runtime, e.g. `~/.claude/settings.json`)

## Machine-local config (not in this repo)

Anything that differs per machine lives in un-managed sidecar files that the
managed configs pull in. These are **not** committed here — create them by
hand on each machine. They're how the same repo works on a personal Mac and a
work Mac without conflict.

| Managed file | Loads | Put here |
|---|---|---|
| `~/.zshrc` | `~/.zshrc.local.pre` (early), `~/.zshrc.local` (late) | Node version manager (nvm at work), vendor shell integrations |
| `~/.zprofile` | `~/.zprofile.local.pre`, `~/.zprofile.local` | login-shell-only machine bits |
| `~/.gitconfig` | `~/.gitconfig.local` (via `[include]`) | work email scoped to work repos via `[includeIf "gitdir:~/work/"]`, signing keys |
| `~/.claude/CLAUDE.md` | `~/.claude/CLAUDE.local.md` (via Claude Code `@import`) | machine-specific Claude Code rules |

The repo itself installs **no Node runtime or version manager** — Node is
delegated to `~/.zshrc.local` so a work machine can use nvm and a personal one
can do whatever it likes.

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

