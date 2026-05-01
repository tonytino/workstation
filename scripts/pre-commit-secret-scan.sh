#!/usr/bin/env bash
# Pre-commit hook: block commits that contain secrets.
# Install with: ln -s ../../scripts/pre-commit-secret-scan.sh .git/hooks/pre-commit
set -euo pipefail

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks not installed. Install: brew install gitleaks"
  exit 1
fi

# Scan only staged changes, not full history.
gitleaks protect --staged --redact --verbose
