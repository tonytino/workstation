#!/usr/bin/env bash
# Install the 1Password app and CLI, then pause for user sign-in.
# `op` is required by chezmoi templates that read secrets from 1Password.
set -euo pipefail

echo "Installing 1Password app + CLI..."

# `brew bundle` from a heredoc is idempotent (skips already-installed entries).
brew bundle --file=- <<'BREWFILE'
cask "1password"
cask "1password-cli"
BREWFILE

# Append a human-readable follow-up for bootstrap's final checklist. No-op when
# run standalone (FOLLOWUPS_FILE unset), so this script stays usable on its own.
record_followup() {
  if [ -n "${FOLLOWUPS_FILE:-}" ]; then
    printf '%s\n' "$1" >>"${FOLLOWUPS_FILE}"
  fi
}

echo
echo "Next: get the 'op' CLI authenticated so chezmoi templates can read"
echo "secrets from 1Password. Two supported ways:"
echo
echo "  A) Desktop app integration (preferred):"
echo "     Open 1Password and sign in, then Settings > Developer > enable"
echo "     'Integrate with 1Password CLI'. Quit and relaunch the app, open a"
echo "     NEW terminal window, and approve the Touch ID prompt on first use."
echo
echo "  B) CLI-native sign-in (use this if integration is blocked -- e.g. macOS"
echo "     privacy settings deny access to the 1Password group container, which"
echo "     surfaces as 'op whoami: no account found for filter'):"
echo "       op account add --address my.1password.com --email <you@example.com>"
echo "       op signin"
echo

# Verify `op` can reach 1Password, retrying until it works or the user skips.
# Prompts read from /dev/tty, never stdin: in remote-mode bootstrap stdin is the
# curl pipe, so a read from stdin would get EOF instead of the user's keystroke.
while ! op whoami >/dev/null 2>&1; do
  echo "'op whoami' cannot reach 1Password yet (no authenticated account)." >/dev/tty
  printf '%s' "Press Enter to re-check, or type 's' to skip 1Password setup: " >/dev/tty
  read -r reply </dev/tty || reply="s"
  case "${reply}" in
    s|S)
      echo "Skipping 1Password CLI setup. Steps that read secrets will fall back"
      echo "to interactive prompts where possible."
      record_followup "Finish 1Password CLI auth so 'op whoami' succeeds, then re-run scripts/install-1password.sh"
      exit 0
      ;;
  esac
done

echo "1Password CLI authenticated."
