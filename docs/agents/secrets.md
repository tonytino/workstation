# Secrets handling

**Hard rule: nothing secret lands in the repo. Ever.** Not in `.tmpl` files, not in comments, not as default values, not in CI configs.

## 1Password CLI is read-only

Agents may only invoke read/list operations against `op`: `op read`, `op item get`, `op item list`, `op vault list`, `op whoami`. Never any create, edit, or delete variant. The user is the sole writer to the 1Password vault.

When automation needs a new 1Password item to exist, tell the user the vault name, item title, and field names; they create it. The script then reads from it.

## Two ways to source secrets at apply time

1. **1Password CLI (`op`)** — chezmoi templates call `{{ onepasswordRead "op://Vault/Item/field" }}`. `bootstrap.sh` stage 3 ensures `op` is signed in via the desktop app before stage 5 renders the templates.
2. **Interactive prompt** — `read -p "..."` inside a helper script. Use this when the value can't reasonably live in 1Password (e.g., a one-shot decision the user has to make at install time, or a passphrase that should never be stored).

## Existing 1Password references

| Reference | Used by |
|---|---|
| `op://Personal/Git Identity/email` | `home/dot_gitconfig.tmpl`, `scripts/provision-ssh.sh` (SSH key comment) |
| `op://Personal/Git Identity/name` | `home/dot_gitconfig.tmpl` |

## Adding a new secret

1. **Tell the user** the vault, item title, and field name they need to create. Wait for confirmation. Do not run any `op` write command.
2. Reference the new field in the chezmoi template via `{{ onepasswordRead "op://Personal/<Item>/<field>" }}`.
3. Verify the user's entry resolves: `op read 'op://...'` should print the value.
4. Add a row to the table above so the next agent knows the reference exists.

## What NOT to do

- **Don't accept secrets via CLI args.** They leak into shell history and `ps` output.
- **Don't accept secrets via environment variables** beyond what `op` already manages. Env vars leak into child processes.
- **Don't write secrets to predictable temp paths.** Use `mktemp` and trap-cleanup.
- **Don't log secret values to stdout, stderr, or files.** No `set -x` in scripts that handle secrets.
- **Don't `cat` a rendered chezmoi file just to "verify" it.** Use `chezmoi diff` (which redacts) or trust the apply.
- **Don't write to 1Password.** No `op item create`, `op item edit`, `op item delete`, or any other state-changing `op` subcommand.
