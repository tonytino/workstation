#!/usr/bin/env bash
# Install Homebrew if missing. Idempotent.
set -euo pipefail

if command -v brew >/dev/null 2>&1; then
  echo "Homebrew already installed ($(brew --version | head -1))"
  exit 0
fi

echo "Installing Homebrew..."
echo "This uses the official installer from https://brew.sh."
echo "It will prompt for your sudo password."
read -p "Continue? [y/N] " -n 1 -r REPLY
echo
[[ "$REPLY" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

# Pinned to the official Homebrew installer URL.
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Configure shell environment so subsequent stages of bootstrap.sh find brew
# without needing a fresh shell.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

echo "Homebrew installed."
