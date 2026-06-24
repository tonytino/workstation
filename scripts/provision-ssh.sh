#!/usr/bin/env bash
# Generate an ed25519 SSH key, add it to ssh-agent + Apple Keychain, and
# register the public key with GitHub.
#
# Security:
# - Passphrase is prompted interactively by ssh-keygen. Never accepted via
#   env var, file, or command-line argument.
# - Private key never leaves the machine. Only the .pub is sent to GitHub.
# - Skips cleanly if a key already exists at the target path.
set -euo pipefail

KEY_PATH="${HOME}/.ssh/id_ed25519"

mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"

if [ -f "${KEY_PATH}" ]; then
  echo "SSH key already exists at ${KEY_PATH} -- skipping generation."
else
  echo "Generating new ed25519 SSH key at ${KEY_PATH}"
  echo "You will be prompted for a passphrase. Use a strong one --"
  echo "it gets cached in macOS Keychain so you only enter it once."

  # Comment uses the email on the user's git identity. Prefer the value already
  # resolved by bootstrap.sh (WS_GIT_EMAIL); else read from 1Password against the
  # resolved vault (WS_OP_VAULT, default Personal); else prompt. The comment goes
  # in the public key only; not a secret.
  COMMENT="${WS_GIT_EMAIL:-}"
  if [ -z "${COMMENT}" ]; then
    COMMENT="$(op read "op://${WS_OP_VAULT:-Personal}/Git Identity/email" 2>/dev/null || true)"
  fi
  if [ -z "${COMMENT}" ]; then
    read -p "Enter email to use as the SSH key comment: " COMMENT
  fi

  ssh-keygen -t ed25519 -C "${COMMENT}" -f "${KEY_PATH}"
fi

echo "Adding key to ssh-agent + Apple Keychain..."
# --apple-use-keychain caches the passphrase in Keychain so it auto-unlocks.
ssh-add --apple-use-keychain "${KEY_PATH}"

echo "Registering public key with GitHub..."
if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not installed. Install it (brew install gh) and re-run."
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "gh is not authenticated. Launching 'gh auth login' (browser-based)..."
  gh auth login
fi

# Use the short hostname (not ComputerName) to avoid leaking macOS defaults
# like "Anthony's MacBook" into log surfaces.
KEY_TITLE="$(hostname -s)-$(date +%Y%m%d)"

# Capture output to a private temp file (mktemp avoids predictable-path
# symlink attacks). Cleaned up on exit.
LOG="$(mktemp -t gh-ssh-add.XXXXXX)"
trap 'rm -f "${LOG}"' EXIT

# `gh ssh-key add` is idempotent against the same key content; if the key
# is already registered, gh prints a message and exits non-zero. Tolerate.
if gh ssh-key add "${KEY_PATH}.pub" --title "${KEY_TITLE}" 2>&1 | tee "${LOG}"; then
  echo "SSH key registered with GitHub as '${KEY_TITLE}'"
else
  if grep -q "key is already in use" "${LOG}"; then
    echo "SSH key was already registered with GitHub."
  else
    echo "Failed to register SSH key with GitHub. Output above."
    exit 1
  fi
fi

# Quick functional test.
echo "Verifying SSH access to github.com..."
if ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
  echo "GitHub SSH OK"
else
  echo "GitHub SSH test inconclusive -- try: ssh -T git@github.com"
fi
