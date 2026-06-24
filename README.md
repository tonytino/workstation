# workstation

Personal macOS workstation setup, managed by [chezmoi](https://chezmoi.io).
One command on a fresh Mac brings it to a working development state.

## Bootstrap a new Mac

macOS only — `bootstrap.sh` asserts Darwin and installs macOS-only apps via
Homebrew casks. Run it from an **interactive shell**: several stages prompt you
(1Password sign-in, SSH key passphrase, `gh` login).

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tonytino/workstation/main/bootstrap.sh)"
```

Piped from `curl`, the script first clones itself to `~/.local/share/chezmoi`
and re-executes from there. Nothing needs to be installed up front — stage 3
installs the 1Password app and pauses for you to sign in and enable CLI
integration before any secrets are read.

Already set this machine up once? Re-running is safe — see
[Re-running on an already-configured machine](#re-running-on-an-already-configured-machine).

## What it does

Stages run in order (numbering is automatic in `bootstrap.sh`):

1. Pre-flight checks (assert macOS, cache sudo).
2. Install Homebrew (official installer).
3. Install the 1Password app + `op` CLI; pause for manual sign-in and CLI
   integration.
4. Install chezmoi.
5. Resolve the Git identity (1Password vault, name, email) in shell — `op read`
   with an interactive prompt fallback — then `chezmoi init` once to persist it
   into chezmoi `[data]` (so the next stage doesn't re-prompt).
6. `chezmoi apply` — renders every template under `home/` into `$HOME` through a
   non-destructive guard: additive changes apply silently, but any file that
   already exists prompts before being overwritten (skip / overwrite / backup /
   diff), with a tip on preserving content via `.local` sidecars. Skipped files
   are listed in the final checklist.
7. `brew bundle` against `macos/Brewfile` — CLIs, fonts, casks.
8. `macos/defaults.sh` — curated, reversible `defaults write` commands (also
   writes an undo script).
9. `gh auth login` (or `gh auth refresh`) with the `admin:public_key` scope so
   the next stage can register an SSH key.
10. Generate an ed25519 SSH key (interactive passphrase), add it to ssh-agent
    + Apple Keychain, register the public key with GitHub via `gh`.
11. Install Claude Code (official installer); user runs `/login` interactively.
12. Clone the private `claude-memory` repo into the Claude Code memory dir,
    skipping gracefully with a recorded follow-up if the remote is unreachable.
13. Symlink the gitleaks pre-commit hook into the clone's `.git/hooks`.
14. Print a manual follow-up checklist.

## Re-running on an already-configured machine

Re-running is safe and idempotent — do it to pick up repo changes, finish a run
that was interrupted (e.g. a network blip), or just re-assert the config. Two
ways, depending on what changed:

- **Re-run `bootstrap.sh`** (the same one-liner above). Every stage is
  idempotent: already-installed tools are skipped, `brew bundle` only adds
  what's missing, `defaults.sh` re-asserts settings (and regenerates its undo
  script), and the **guarded** `chezmoi apply` only touches what differs. Use
  this after a partial/failed run, to pull in new tooling (Brewfile additions),
  or the first time you apply on a machine that already has hand-rolled
  dotfiles.
- **`chezmoi diff` + `chezmoi apply`** (see [Day-to-day use](#day-to-day-use)).
  For routine dotfile edits once the machine is already managed by this repo.
  Note this is a **bare** `chezmoi apply` — it does *not* go through bootstrap's
  guard, so always preview with `chezmoi diff` first.

### The non-destructive guard

When run through `bootstrap.sh`, the apply step uses
`scripts/chezmoi-apply-guarded.sh`, which protects pre-existing files:

- Purely additive changes (the file doesn't exist yet) apply silently.
- Any file that **already exists and would change** prompts per-file:
  `skip` / `overwrite` / `backup` (copies the original to
  `~/.workstation-backups/<timestamp>/` first) / `diff`.
- With no TTY (non-interactive), every conflict defaults to **skip** — it never
  clobbers silently.
- When the conflicting file has a machine-local sidecar (e.g. `~/.zshrc.local`),
  the prompt tells you how to preserve your current content.
- Anything skipped — files, plus stages that gracefully bailed (e.g. an
  unreachable private repo) — is listed in the final checklist with the exact
  command to finish it later.

First time on a machine with existing dotfiles, the cleanest path is to move the
content you want to keep into the `.local` sidecars (see
[Machine-local config](#machine-local-config-not-in-this-repo)) before applying
— or just choose `backup` at each prompt and reconcile afterward.

## Security model

- **No secrets in the repo, ever.** Templates reference 1Password items by
  name (e.g. `op://<vault>/Git Identity/email`, where `<vault>` is the prompted
  `opVault` var). The Git identity is resolved from 1Password at `chezmoi init`
  time (with an interactive prompt fallback) and persisted to chezmoi `[data]`;
  the actual values land on disk only in the rendered files in `$HOME`.
- Anything `op` cannot supply is prompted interactively at install/apply time.
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
│   ├── .chezmoi.toml.tmpl           # config template — prompts + persists [data]
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
│   ├── chezmoi-apply-guarded.sh
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
| `~/.ssh/config` | `~/.ssh/config.local` (via `Include`, first-match-wins) | machine-specific host blocks, jump hosts |

For git specifically, the managed `~/.gitconfig` ends with
`[include] path = ~/.gitconfig.local`, so a per-machine `~/.gitconfig.local`
can override the 1Password-sourced identity — e.g. scope a work email to work
repos with `[includeIf "gitdir:~/work/"]`. The 1Password vault holding the
`Git Identity` item is itself prompted once at `chezmoi init` (the `opVault`
data var, defaulting to `Personal`), so a work machine can point at a
differently named vault without editing the repo.

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

