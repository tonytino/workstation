# Secrets handling

**Hard rule: nothing secret lands in the repo. Ever.** Not in `.tmpl` files, not in comments, not as default values, not in CI configs.

## 1Password CLI is read-only

Agents may only invoke read/list operations against `op`: `op read`, `op item get`, `op item list`, `op vault list`, `op whoami`. Never any create, edit, or delete variant. The user is the sole writer to the 1Password vault.

When automation needs a new 1Password item to exist, tell the user the vault name, item title, and field names; they create it. The script then reads from it.

## Two ways to source secrets at apply time

1. **1Password CLI (`op`)** — chezmoi templates call `{{ onepasswordRead "op://Vault/Item/field" }}`. `bootstrap.sh` stage 3 ensures `op` is signed in via the desktop app before later stages read from it. Note `onepasswordRead` hard-errors (no try/catch in Go templates) if the item can't be resolved, which aborts the whole render — only use it where a failure-to-resolve should legitimately abort.
2. **Interactive prompt** — `read -p "..."` inside a helper script. Use this when the value can't reasonably live in 1Password (e.g., a one-shot decision the user has to make at install time, or a passphrase that should never be stored).

### Shell-resolve + persist pattern (graceful fallback)

For values that should degrade gracefully when `op` can't resolve them, resolve in **shell** and persist into chezmoi `[data]` rather than calling `onepasswordRead` in a file template. The Git identity uses this: `bootstrap.sh` stage 5 reads the vault/name/email via `op read ... || true` with an interactive `/dev/tty` fallback, exports `WS_OP_VAULT`/`WS_GIT_NAME`/`WS_GIT_EMAIL`, and a single `chezmoi init` persists them into `[data]` (`opVault`/`gitName`/`gitEmail`). `home/dot_gitconfig.tmpl` then just reads `{{ .gitName }}`/`{{ .gitEmail }}`. This means a missing/locked/misnamed vault prompts instead of aborting the render.

## Existing 1Password references

| Reference | Used by |
|---|---|
| `op://<opVault>/Git Identity/name` | resolved in shell (`bootstrap.sh` stage 5) → persisted to `[data]` `gitName` → `home/dot_gitconfig.tmpl` |
| `op://<opVault>/Git Identity/email` | resolved in shell (`bootstrap.sh` stage 5) → persisted to `[data]` `gitEmail` → `home/dot_gitconfig.tmpl`; also reused as the SSH key comment in `scripts/provision-ssh.sh` |

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
