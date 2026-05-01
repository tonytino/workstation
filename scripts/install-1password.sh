#!/usr/bin/env bash
# Install the 1Password app and CLI, then pause for user sign-in.
# `op` is required by chezmoi templates that read secrets from 1Password.
set -euo pipefail

echo "Installing 1Password app + CLI..."

# `brew bundle` from a heredoc is idempotent (skips already-installed entries).
brew bundle --file=- <<'BREWFILE'
cask "1password"
brew "1password-cli"
BREWFILE

echo
echo "Next: open the 1Password app and sign in."
echo "Then in 1Password Preferences > Developer, enable:"
echo "  'Integrate with 1Password CLI'"
echo "This lets the 'op' CLI authenticate via the desktop app instead of"
echo "prompting for your password every time."
read -p "Press Enter once you've signed in and enabled CLI integration... "

# Verify `op` can talk to the desktop app.
if ! op whoami >/dev/null 2>&1; then
  echo
  echo "'op whoami' failed. The CLI cannot reach 1Password."
  echo "Check Settings > Developer > 'Integrate with 1Password CLI'."
  exit 1
fi

echo "1Password CLI authenticated."
