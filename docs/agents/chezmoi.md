# Chezmoi conventions

The source-of-truth for everything that lands in `$HOME` lives under `home/` in this repo. `.chezmoiroot` points chezmoi there. Source files are renamed at apply time according to chezmoi's prefix conventions.

## Prefix rules

| Prefix | Effect |
|---|---|
| `dot_` | Renders to a leading `.` (e.g. `dot_zshrc` → `~/.zshrc`) |
| `private_` | Sets file mode to `0600` |
| `executable_` | Sets the executable bit |
| `.tmpl` (suffix) | File is rendered as a Go template with chezmoi data + functions |

Stack them: `private_dot_ssh/config.tmpl` → `~/.ssh/config` (mode `0600`, templated).

## Template functions used in this repo

- `onepasswordRead "op://..."` — fetches a secret from 1Password CLI at apply time. See [secrets.md](secrets.md).

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
