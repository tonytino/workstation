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
    echo "${LOCAL_REPO} already exists -- pulling latest."
    git -C "${LOCAL_REPO}" pull --ff-only
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
trap 'if [ -n "${SUDO_KEEPALIVE_PID}" ]; then kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true; fi' EXIT
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

# Apply chezmoi (renders templates, lays down configs) ---------------------
banner "chezmoi apply"
# Pass --source explicitly: `chezmoi init --source=...` does NOT persist the
# source dir to config, so a bare `chezmoi apply` would fall back to the
# default (~/.local/share/chezmoi) and silently no-op when run from a clone
# elsewhere. .chezmoiroot inside the repo redirects the source to ./home/.
echo "Applying chezmoi from ${REPO_ROOT} (renders templates, lays down configs)..."
chezmoi apply --source="${REPO_ROOT}"

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
