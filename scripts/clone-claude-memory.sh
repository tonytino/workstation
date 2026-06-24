#!/usr/bin/env bash
# Clone the private claude-memory repo into the Claude Code memory directory.
# Idempotent: if the repo is already present, pulls latest instead.
#
# Claude Code stores per-project memory under
#   ~/.claude/projects/<encoded-cwd>/memory
# where <encoded-cwd> is the absolute working directory with each "/" replaced
# by "-". The primary working directory for this user is ~/src, so we derive
# the encoded path from that.
set -euo pipefail

REPO="git@github.com:tonytino/claude-memory.git"
WORKDIR="${HOME}/src"

# Encode the working directory the way Claude Code does: replace "/" with "-".
ENCODED="$(printf '%s' "${WORKDIR}" | sed 's|/|-|g')"
MEM_DIR="${HOME}/.claude/projects/${ENCODED}/memory"

# Append a human-readable follow-up instruction for the bootstrap's final
# checklist. No-op when run standalone (FOLLOWUPS_FILE unset), so this script
# stays usable on its own.
record_followup() {
  if [ -n "${FOLLOWUPS_FILE:-}" ]; then
    printf '%s\n' "$1" >>"${FOLLOWUPS_FILE}"
  fi
}

if [ -d "${MEM_DIR}/.git" ]; then
  echo "claude-memory already present at ${MEM_DIR} -- pulling latest."
  git -C "${MEM_DIR}" pull --ff-only
  exit 0
fi

# If a non-git memory dir already exists (e.g. local-only memories), don't
# clobber it -- warn and skip gracefully so the user can reconcile manually.
if [ -d "${MEM_DIR}" ] && [ -n "$(ls -A "${MEM_DIR}" 2>/dev/null)" ]; then
  echo "A non-empty, non-git memory dir exists at ${MEM_DIR}." >&2
  echo "Refusing to overwrite. Back it up, remove it, and re-run this script." >&2
  record_followup "Reconcile the existing memory dir at ${MEM_DIR} (back it up / remove it), then re-run scripts/clone-claude-memory.sh"
  exit 0
fi

# Probe the remote before cloning. If SSH isn't set up yet (or there's no
# access), skip gracefully so the bootstrap can continue instead of aborting.
if ! git ls-remote "${REPO}" >/dev/null 2>&1; then
  echo "Cannot reach ${REPO} (SSH not set up yet, or no access). Skipping." >&2
  record_followup "Clone Claude memory: once SSH access to ${REPO} works, re-run scripts/clone-claude-memory.sh"
  exit 0
fi

echo "Cloning claude-memory into ${MEM_DIR}..."
mkdir -p "$(dirname "${MEM_DIR}")"
if ! git clone "${REPO}" "${MEM_DIR}"; then
  echo "Clone of ${REPO} failed. Skipping." >&2
  record_followup "Clone Claude memory: clone of ${REPO} failed; re-run scripts/clone-claude-memory.sh once the cause is resolved"
  exit 0
fi
echo "claude-memory cloned. Use 'mem-sync' (zsh function) to push updates."
