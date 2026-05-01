#!/usr/bin/env bash
# Install chezmoi via Homebrew. Idempotent.
set -euo pipefail

if command -v chezmoi >/dev/null 2>&1; then
  echo "chezmoi already installed ($(chezmoi --version | head -1))"
  exit 0
fi

echo "Installing chezmoi..."
brew install chezmoi
echo "chezmoi installed."
