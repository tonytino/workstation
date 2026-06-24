#!/usr/bin/env bash
# Non-destructive `chezmoi apply` wrapper.
#
# A bare `chezmoi apply` blindly overwrites pre-existing files in $HOME. This
# guard inspects the pending changes first and, for any change that would
# modify or delete a file that already exists, prompts the user per-file:
#   [s]kip / [o]verwrite / [b]ackup then overwrite / [d]iff
# When the conflicting file has a machine-local sidecar (e.g. ~/.zshrc.local),
# the prompt also hints how to preserve the user's current content.
# Purely additive changes (the destination does not exist yet) are applied
# without prompting. Skipped files are recorded so the caller can list them in
# the final follow-up checklist with the command to adopt them later.
#
# Usage:
#   chezmoi-apply-guarded.sh <chezmoi-source-dir>
#
# Environment:
#   SKIPPED_FILE  Path to a file where skipped target paths are appended, one
#                 per line. If unset, a mktemp is used (and not cleaned up here;
#                 the caller owns SKIPPED_FILE's lifecycle).
#
# Safety:
# - Reads choices from /dev/tty, never stdin (stdin may be a curl pipe).
# - With no usable TTY, every modify/delete defaults to SKIP (recorded), never
#   a silent overwrite.
# - Never runs a bare `chezmoi apply` (that would apply everything); applies
#   only the explicitly approved target paths.
set -euo pipefail

SRC="${1:?usage: chezmoi-apply-guarded.sh <chezmoi-source-dir>}"
SKIPPED_FILE="${SKIPPED_FILE:-$(mktemp)}"

# One timestamp for the whole run so all backups land under the same dir.
ts="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${HOME}/.workstation-backups/${ts}"

# Target paths approved for application. Kept as an array so paths with spaces
# survive intact when passed to `chezmoi apply`.
apply_paths=()

# Record a target path as skipped (appended to SKIPPED_FILE).
record_skip() {
  echo "$1" >>"${SKIPPED_FILE}"
}

# True if we have an interactive terminal to prompt on.
have_tty() {
  [ -r /dev/tty ] && [ -t 0 ]
}

# Back up the current destination file, preserving its relative path under the
# timestamped backup root. Echoes the backup location.
backup_dest() {
  local dest="$1" rel="$2" backup
  backup="${BACKUP_ROOT}/${rel}"
  mkdir -p "$(dirname "${backup}")"
  cp -p "${dest}" "${backup}"
  echo "Backed up ${dest} -> ${backup}"
}

# Print a hint when the conflicting file has a machine-local sidecar, so the
# user can preserve their current content (copy it into the sidecar) instead of
# losing it on overwrite. Echoes nothing for files without a sidecar.
sidecar_hint() {
  # The ~ in these strings is literal display text for the user, not a path to
  # be expanded, so SC2088 (tilde does not expand in quotes) does not apply.
  # shellcheck disable=SC2088
  case "$1" in
    .zshrc)
      echo "~/.zshrc sources ~/.zshrc.local -- copy anything you want to keep into ~/.zshrc.local before overwriting." ;;
    .zprofile)
      echo "~/.zprofile sources ~/.zprofile.local -- copy anything you want to keep into ~/.zprofile.local before overwriting." ;;
    .gitconfig)
      echo "~/.gitconfig includes ~/.gitconfig.local -- move any settings you want to keep into ~/.gitconfig.local before overwriting." ;;
    .ssh/config)
      echo "~/.ssh/config includes ~/.ssh/config.local -- copy any host blocks you want to keep into ~/.ssh/config.local before overwriting." ;;
    .claude/CLAUDE.md)
      echo "~/.claude/CLAUDE.md imports ~/.claude/CLAUDE.local.md -- move any rules you want to keep into ~/.claude/CLAUDE.local.md before overwriting." ;;
  esac
}

# Prompt for a single risky (M/D) change and act on the answer. Adds to
# apply_paths on overwrite/backup, records a skip otherwise.
prompt_for_change() {
  local rel="$1" dest="$2" choice hint
  printf '%s\n' "Conflict: ${dest} already exists and would be changed." >/dev/tty
  hint="$(sidecar_hint "${rel}")"
  if [ -n "${hint}" ]; then
    printf '  Tip: %s\n' "${hint}" >/dev/tty
  fi
  while true; do
    printf '%s' "  [s]kip / [o]verwrite / [b]ackup then overwrite / [d]iff: " >/dev/tty
    read -r choice </dev/tty || choice="s"
    case "${choice}" in
      s|S)
        echo "Skipping ${dest}." >/dev/tty
        record_skip "${dest}"
        return 0
        ;;
      o|O)
        apply_paths+=("${dest}")
        return 0
        ;;
      b|B)
        if [ -f "${dest}" ]; then
          backup_dest "${dest}" "${rel}" >/dev/tty
        else
          echo "Nothing to back up (${dest} is not a regular file); proceeding." >/dev/tty
        fi
        apply_paths+=("${dest}")
        return 0
        ;;
      d|D)
        chezmoi diff --source="${SRC}" "${dest}" >/dev/tty 2>&1 || true
        # Loop re-prompts the same file.
        ;;
      *)
        echo "Unrecognized choice '${choice}'." >/dev/tty
        ;;
    esac
  done
}

echo "Inspecting pending chezmoi changes from ${SRC}..."

# `chezmoi status` prints two status columns then a destination-relative path.
# The SECOND column is what `apply` would do to the target:
#   A = add (destination absent)  -> additive, always apply, no prompt
#   M = modify (exists, differs)  -> risky, prompt
#   D = delete (target removed)   -> destructive, prompt
#   space / no change             -> ignore
status_output="$(chezmoi status --source="${SRC}")"

while IFS= read -r line; do
  [ -n "${line}" ] || continue
  # Columns 1-2 are status flags; the path starts at column 4 (after a space).
  apply_op="${line:1:1}"
  rel="${line:3}"
  [ -n "${rel}" ] || continue
  dest="${HOME}/${rel}"

  case "${apply_op}" in
    A)
      apply_paths+=("${dest}")
      ;;
    M|D)
      if have_tty; then
        prompt_for_change "${rel}" "${dest}"
      else
        echo "No TTY available: skipping existing file ${dest} to avoid clobbering it."
        record_skip "${dest}"
      fi
      ;;
    *)
      # No change or unhandled flag -- ignore.
      ;;
  esac
done <<<"${status_output}"

# Apply only the approved set. Never run a bare `chezmoi apply`: with no path
# arguments it would apply EVERYTHING, defeating the guard. The
# "${arr[@]+...}" form keeps `set -u` happy when the array is empty.
applied_count="${#apply_paths[@]}"
if [ "${applied_count}" -gt 0 ]; then
  echo "Applying ${applied_count} change(s) from ${SRC}..."
  chezmoi apply --source="${SRC}" "${apply_paths[@]+"${apply_paths[@]}"}"
else
  echo "Nothing to apply (no additive changes and no conflicts approved)."
fi

skipped_count=0
if [ -s "${SKIPPED_FILE}" ]; then
  skipped_count="$(grep -c '' "${SKIPPED_FILE}")"
fi

echo "chezmoi guarded apply summary: ${applied_count} applied, ${skipped_count} skipped."
