# Chezmoi conventions

The source-of-truth for everything that lands in `$HOME` lives under `home/` in this repo. `.chezmoiroot` points chezmoi there. Source files are renamed at apply time according to chezmoi's prefix conventions.

## Prefix rules

| Prefix | Effect |
|---|---|
| `dot_` | Renders to a leading `.` (e.g. `dot_zshrc` → `~/.zshrc`) |
| `private_` | Sets file mode to `0600` |
| `executable_` | Sets the executable bit |
| `.tmpl` (suffix) | File is rendered as a Go template with chezmoi data + functions |
| `modify_` | Executable script: receives the current target file on stdin, emits new contents on stdout |

Stack them: `private_dot_ssh/config.tmpl` → `~/.ssh/config` (mode `0600`, templated).

## Template functions used in this repo

- `onepasswordRead "op://..."` — fetches a secret from 1Password CLI at apply time. Hard-errors (aborting the render) if the item can't be resolved. See [secrets.md](secrets.md).
- `promptStringOnce . "key" "prompt" ["default"]` — used only in the config template `home/.chezmoi.toml.tmpl` (evaluated at `chezmoi init`), where the result is persisted to `[data]` and reused by later apply/status without re-prompting.

### Git identity: shell-resolved, persisted to `[data]`

The Git identity is NOT read via `onepasswordRead` in `dot_gitconfig.tmpl`. Instead `bootstrap.sh` resolves the vault/name/email in shell (op with an interactive fallback), exports `WS_OP_VAULT`/`WS_GIT_NAME`/`WS_GIT_EMAIL`, and a single `chezmoi init` evaluates `home/.chezmoi.toml.tmpl` to persist them into `[data]` (`opVault`/`gitName`/`gitEmail`). The config template prefers the `WS_*` env vars and falls back to `promptStringOnce` for standalone `chezmoi init` runs. `dot_gitconfig.tmpl` then reads `{{ .gitName }}`/`{{ .gitEmail }}`. This avoids the render-aborting failure mode of `onepasswordRead` and the double prompt of evaluating the config template on both `status` and `apply`.

## Per-machine config: three mechanisms

Pick by file format. Goal: the same repo applies cleanly on every machine, and machine-specific bits stay out of the repo.

1. **Native include + `.local` sidecar** (preferred when the format supports it). The managed file pulls in an un-managed `~/.<x>.local`:
   - zsh: `[ -f ~/.zshrc.local ] && source ~/.zshrc.local` (also `.local.pre` sourced early)
   - git: `[include] path = ~/.gitconfig.local` (and `[includeIf "gitdir:~/work/"]` for work-scoped identity)
   - The `.local` files are NOT committed here — created by hand per machine.
2. **`modify_` script** — for structured formats with no include (JSON/plist). `modify_settings.json` merges our managed keys and preserves runtime-written keys (e.g. `feedbackSurveyState`) so `chezmoi status` stays clean.
3. **Template conditionals** — `{{ if eq .chezmoi.hostname "..." }}` when you want per-machine logic kept in-repo (synced, non-sensitive).

## settings.json never fully managed

`~/.claude/settings.json` uses mechanism 2 (`modify_settings.json`). Claude Code rewrites that file at runtime; a plain managed copy would show perpetual drift. The modify script falls back to emitting the managed config verbatim when the file is absent or `jq` isn't installed yet (chezmoi apply runs before the Brewfile stage on a fresh machine).

## Adding a new dotfile

1. Drop the source file under `home/` with the right prefix.
2. If it has secrets, add the `.tmpl` suffix and use `onepasswordRead`. Update [secrets.md](secrets.md) with the new reference.
3. Run `chezmoi diff` locally (with `op` signed in) to preview the rendered output without applying.
4. Run `chezmoi apply` once the diff looks right.

## Day-to-day commands

| Command | Effect |
|---|---|
| `chezmoi diff` | Show what would change in `$HOME` |
| `chezmoi apply` | Apply changes |
| `chezmoi status` | Show drift between source and `$HOME` |
| `chezmoi re-add <path>` | Capture an in-place edit back into the source tree |

## Editing rendered files in `$HOME`

Don't. Edit the source under `home/` (or `~/.local/share/chezmoi/`) and run `chezmoi apply`. If you've already edited a rendered file in place, recover it with `chezmoi re-add <path>` to push the change back into the source tree.
