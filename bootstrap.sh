#!/usr/bin/env bash
# bootstrap.sh -- one-command setup for a fresh macOS development machine.
#
# Usage on a clean Mac:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tonytino/workstation/main/bootstrap.sh)"
#
# This script is idempotent: re-running it on a configured machine is safe.
# Each stage is its own helper script under scripts/.
#
# Security:
# - No secrets are embedded anywhere. All secret material is either fetched
#   from 1Password at apply time (via chezmoi templates + op) or prompted
#   interactively from the user.
# - Every third-party install uses an official, pinned URL.
# - Read prompts pause execution; nothing destructive runs without consent.
set -euo pipefail

REPO_URL="https://github.com/tonytino/workstation.git"
LOCAL_REPO="${HOME}/.local/share/chezmoi"

# When the script is piped from curl, scripts/ files are not on disk yet.
# Two modes:
#   1) Local mode: script is run from inside a clone -- use ./scripts/*.
#   2) Remote mode: piped from curl -- bootstrap clones the repo first,
#      then re-execs from the local clone.
if [ ! -f "$(dirname "$0")/scripts/install-homebrew.sh" ]; then
  echo "Detected remote-mode bootstrap (piped from curl)."
  echo "Cloning the workstation repo to ${LOCAL_REPO}..."
  if ! command -v git >/dev/null 2>&1; then
    echo "git not found. Install Xcode Command Line Tools first:"
    echo "  xcode-select --install"
    exit 1
  fi
  if [ -d "${LOCAL_REPO}" ]; then
    echo "${LOCAL_REPO} already exists -- syncing to origin/main."
    # Force a predictable state: fetch, switch to main, fast-forward. Guards
    # against an existing clone left on a feature branch (which would pull the
    # wrong content or fail noisily).
    git -C "${LOCAL_REPO}" fetch origin
    git -C "${LOCAL_REPO}" checkout main
    git -C "${LOCAL_REPO}" pull --ff-only origin main
  else
    mkdir -p "$(dirname "${LOCAL_REPO}")"
    git clone "${REPO_URL}" "${LOCAL_REPO}"
  fi
  echo "Re-executing bootstrap from ${LOCAL_REPO}/bootstrap.sh"
  exec bash "${LOCAL_REPO}/bootstrap.sh"
fi

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="${REPO_ROOT}/scripts"
MACOS_DIR="${REPO_ROOT}/macos"

# The guarded chezmoi-apply stage records any files it skipped (to avoid
# clobbering pre-existing content) here, one path per line. The final
# follow-up checklist reads it back. Cleaned up on EXIT (see trap below).
SKIPPED_FILE="$(mktemp)"
export SKIPPED_FILE

# Stages that depend on a private/external resource degrade to skip-with-
# instructions instead of hard-failing. Each such stage appends a human-readable
# follow-up instruction here, one per line; the final checklist reads it back.
# Cleaned up on EXIT (see trap below).
FOLLOWUPS_FILE="$(mktemp)"
export FOLLOWUPS_FILE

# Stage numbering is automatic. banner() increments a counter, and TOTAL is
# derived by counting the stage invocations in this file. Add, remove, or
# reorder `banner "..."` calls freely -- nothing needs manual renumbering.
STAGE=0
TOTAL="$(grep -cE '^banner ' "${BASH_SOURCE[0]}")"

banner() {
  STAGE=$((STAGE + 1))
  echo
  echo "=============================================================="
  echo " [${STAGE}/${TOTAL}] $1"
  echo "=============================================================="
}

# Pre-flight -------------------------------------------------------------------
banner "Pre-flight checks"
if [ "$(uname)" != "Darwin" ]; then
  echo "This script is macOS-only. Aborting."
  exit 1
fi
echo "Asking for sudo up-front so later steps don't re-prompt..."
sudo -v
# Keep sudo alive until the script ends. Trap is installed BEFORE forking the
# keepalive so a crash between fork and trap-install can't leave it orphaned.
SUDO_KEEPALIVE_PID=""
trap 'if [ -n "${SUDO_KEEPALIVE_PID}" ]; then kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true; fi; rm -f "${SKIPPED_FILE}"; rm -f "${FOLLOWUPS_FILE}"' EXIT
( while true; do sudo -n true; sleep 30; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!

# Homebrew -----------------------------------------------------------------
banner "Homebrew"
bash "${SCRIPTS}/install-homebrew.sh"
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# 1Password app + CLI ------------------------------------------------------
banner "1Password app + CLI"
bash "${SCRIPTS}/install-1password.sh"

# chezmoi ------------------------------------------------------------------
banner "chezmoi"
bash "${SCRIPTS}/install-chezmoi.sh"

# Git identity + chezmoi init ----------------------------------------------
banner "Git identity + chezmoi init"
# Resolve the Git identity (1Password vault, name, email) HERE, in shell,
# rather than in the gitconfig template. Why:
# - `onepasswordRead` inside a file template (dot_gitconfig.tmpl) HARD-ERRORS
#   if the item can't be resolved (missing/locked/misnamed vault). Go templates
#   have no try/catch, so a single failed read aborts the whole render (#26).
#   Resolving in shell lets us fall back gracefully to an interactive prompt.
# - We persist these values into chezmoi's [data] via a single `chezmoi init`
#   below, so the subsequent guarded status/apply reuse them WITHOUT
#   re-prompting (fixes the double vault prompt from #25).
# Prompts read from /dev/tty, never stdin: in remote-mode bootstrap stdin is
# the curl pipe, so `read` from stdin would get garbage or EOF.
if [ -z "${WS_OP_VAULT:-}" ]; then
  printf '%s' "1Password vault for Git Identity [Personal]: " >/dev/tty
  read -r WS_OP_VAULT </dev/tty || true
  WS_OP_VAULT="${WS_OP_VAULT:-Personal}"
fi
WS_GIT_NAME="$(op read "op://${WS_OP_VAULT}/Git Identity/name" 2>/dev/null || true)"
if [ -z "${WS_GIT_NAME}" ]; then
  printf '%s' "Git author name: " >/dev/tty
  read -r WS_GIT_NAME </dev/tty || true
fi
WS_GIT_EMAIL="$(op read "op://${WS_OP_VAULT}/Git Identity/email" 2>/dev/null || true)"
if [ -z "${WS_GIT_EMAIL}" ]; then
  printf '%s' "Git author email: " >/dev/tty
  read -r WS_GIT_EMAIL </dev/tty || true
fi
export WS_OP_VAULT WS_GIT_NAME WS_GIT_EMAIL

# Plain `chezmoi init` (NOT --apply): this evaluates the config template
# (home/.chezmoi.toml.tmpl) exactly once, which reads the WS_* env vars above
# and PERSISTS them to ~/.config/chezmoi/chezmoi.toml [data]. The guarded
# status/apply that follows reuse that persisted data, so the vault prompt
# never appears twice (#25).
# Note: the `--source=` FLAG is not itself persisted, but the config template
# writes `sourceDir = {{ .chezmoi.sourceDir }}` into the generated config, so
# after this init bare `chezmoi` commands resolve the right source without
# --source. The apply/status calls below still pass --source explicitly for
# determinism (and because the guard runs before this init on a fresh machine
# has had a chance to take effect on the very first call).
echo "Initializing chezmoi config from ${REPO_ROOT} (persists Git identity to [data])..."
chezmoi init --source="${REPO_ROOT}"

# Apply chezmoi (renders templates, lays down configs) ---------------------
banner "chezmoi apply"
# Pass --source explicitly for determinism. The init above persists `sourceDir`
# into the config (via the template), so bare chezmoi now resolves correctly --
# but being explicit here keeps this stage correct even if that config is stale
# or absent. .chezmoiroot inside the repo redirects the source to ./home/.
#
# Use the guarded wrapper instead of a bare `chezmoi apply`: it applies purely
# additive changes silently, but prompts per-file before overwriting or
# deleting any pre-existing file (skip / overwrite / backup). Files the user
# skips are recorded in SKIPPED_FILE and surfaced in the final checklist.
echo "Applying chezmoi from ${REPO_ROOT} (renders templates, lays down configs)..."
bash "${SCRIPTS}/chezmoi-apply-guarded.sh" "${REPO_ROOT}"

# Brewfile (CLIs, fonts, casks) --------------------------------------------
banner "Brewfile"
brew bundle --file="${MACOS_DIR}/Brewfile"

# macOS defaults -----------------------------------------------------------
banner "macOS defaults"
bash "${MACOS_DIR}/defaults.sh"

# GitHub auth (interactive if not already authed) -------------------------
# Done BEFORE SSH provisioning so 'gh ssh-key add' has the right OAuth scope.
banner "GitHub auth"
REQUIRED_SCOPES="admin:public_key,repo,read:org,workflow"
if gh auth status 2>&1 | grep -q "Token scopes"; then
  echo "gh already authenticated. Refreshing scopes to include admin:public_key..."
  gh auth refresh -h github.com -s admin:public_key || \
    gh auth login --scopes "${REQUIRED_SCOPES}"
else
  gh auth login --scopes "${REQUIRED_SCOPES}"
fi

# SSH key + GitHub registration --------------------------------------------
banner "SSH key + GitHub registration"
bash "${SCRIPTS}/provision-ssh.sh"

# Claude Code -------------------------------------------------------------
banner "Claude Code"
bash "${SCRIPTS}/install-claude-code.sh"

# Claude memory -----------------------------------------------------------
# Clone the private agent-memory repo into place. Runs after SSH provisioning
# so the SSH remote authenticates.
banner "Claude memory"
bash "${SCRIPTS}/clone-claude-memory.sh"

# Pre-commit hook --------------------------------------------------------------
# Wire the repo's gitleaks pre-commit hook into this clone so local commits to
# the workstation repo are scanned before they land (CI is the backstop, not
# the first line). Idempotent; leaves a pre-existing non-symlink hook alone.
banner "Pre-commit secret-scan hook"
if [ -d "${REPO_ROOT}/.git" ]; then
  HOOK_DST="${REPO_ROOT}/.git/hooks/pre-commit"
  if [ -e "${HOOK_DST}" ] && [ ! -L "${HOOK_DST}" ]; then
    echo "Existing non-symlink pre-commit hook found; leaving it untouched."
  else
    ln -sf "../../scripts/pre-commit-secret-scan.sh" "${HOOK_DST}"
    echo "Linked pre-commit secret-scan hook into ${HOOK_DST}."
  fi
else
  echo "No .git dir at ${REPO_ROOT}; skipping pre-commit hook install."
fi

# Manual follow-up checklist ----------------------------------------------
banner "Manual follow-ups"
cat <<'EOF'

Bootstrap complete. A few things require human clicks; do these now:

  1. Magnet (window snapping)
     Open the App Store, search Magnet, and install.
     (Skipped automation here on purpose -- no third-party CLI required.)

  2. Ghostty -- mic permission
     Launch Ghostty, run 'claude', try /voice. macOS will prompt for mic
     access on first use; allow it.

  3. Claude Code -- /login
     Run 'claude' and complete /login if you haven't already.

Verify the install:
  brew --version
  gh auth status
  gh ssh-key list | head
  chezmoi status
  claude --version

EOF

# Surface any files the guarded chezmoi-apply stage skipped to protect existing
# content, with the exact command to adopt each one later.
if [ -s "${SKIPPED_FILE}" ]; then
  echo "Skipped to protect existing files. To adopt any of these later, run:"
  while IFS= read -r skipped_path; do
    [ -n "${skipped_path}" ] || continue
    echo "  chezmoi apply --source=\"${REPO_ROOT}\" \"${skipped_path}\""
  done <"${SKIPPED_FILE}"
  echo
fi

# Surface any stages that degraded to a graceful skip (e.g. a private repo that
# was unreachable), with the human-readable instruction to finish them later.
if [ -s "${FOLLOWUPS_FILE}" ]; then
  echo "Some stages were skipped. To finish them later:"
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    echo "  - ${line}"
  done <"${FOLLOWUPS_FILE}"
  echo
fi
