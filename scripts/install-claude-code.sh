#!/usr/bin/env bash
# Install Claude Code CLI. Idempotent.
# Reference: https://claude.com/claude-code
set -euo pipefail

if command -v claude >/dev/null 2>&1 || [ -x "${HOME}/.claude/local/claude" ]; then
  echo "Claude Code already installed."
  exit 0
fi

echo "Installing Claude Code..."
echo "This uses Anthropic's official installer at https://claude.ai/install.sh"
read -p "Continue? [y/N] " -n 1 -r REPLY
echo
[[ "$REPLY" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

# Official installer hosted on anthropic.com.
curl -fsSL https://claude.ai/install.sh | bash

echo
echo "Next: run 'claude' and complete '/login' interactively."
echo "Authentication uses your Claude.ai account in the browser --"
echo "no API keys are stored on disk."
