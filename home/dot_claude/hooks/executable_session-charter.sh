#!/usr/bin/env bash
# Session charter: re-inject a session's charter doc into Claude's context after
# every compaction, so the original intent survives repeated summaries.
#
# Hook mode (no args): registered as a SessionStart hook with matcher "compact".
# Reads the hook JSON on stdin; if ~/.claude/charters/<session_id> exists, prints
# the charter (everything above a `<!-- charter:end -->` line, or the whole file)
# so Claude Code adds it to context. Unregistered sessions get no output.
#
# CLI mode (used by the /charter skill):
#   session-charter.sh register <charter-path> [session-id]
#   session-charter.sh unregister [session-id]
#   session-charter.sh show [session-id]     # print what the hook would inject
# session-id defaults to $CLAUDE_CODE_SESSION_ID.
set -euo pipefail

REGISTRY="${CLAUDE_CHARTERS_DIR:-${HOME}/.claude/charters}"
END_MARKER='<!-- charter:end -->'

valid_id() { [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]; }

resolve_id() {
  local id="${1:-${CLAUDE_CODE_SESSION_ID:-}}"
  if [ -z "${id}" ] || ! valid_id "${id}"; then
    echo "session id missing or invalid (pass one, or set CLAUDE_CODE_SESSION_ID)" >&2
    exit 1
  fi
  printf '%s' "${id}"
}

emit() { # emit <session-id>; prints nothing if unregistered
  local entry="${REGISTRY}/$1" charter
  [ -f "${entry}" ] || return 0
  charter="$(head -n 1 "${entry}")"
  if [ ! -f "${charter}" ]; then
    echo "This session has a registered charter at ${charter}, but the file is missing. Tell the user."
    return 0
  fi
  echo "Context was just compacted. Below is this session's charter from ${charter}."
  echo "It outranks the compaction summary: where they disagree, follow the charter."
  echo "Re-read the full file before acting, flag anything that looks stale, and follow its update rules."
  echo
  awk -v m="${END_MARKER}" '$0 == m {exit} {print}' "${charter}"
}

case "${1:-}" in
  register)
    path="${2:-}"
    [ -n "${path}" ] && [ -f "${path}" ] || { echo "usage: $0 register <existing-charter-path> [session-id]" >&2; exit 1; }
    id="$(resolve_id "${3:-}")"
    abs="$(cd "$(dirname "${path}")" && pwd)/$(basename "${path}")"
    mkdir -p "${REGISTRY}"
    printf '%s\n' "${abs}" > "${REGISTRY}/${id}"
    echo "registered ${id} -> ${abs}"
    ;;
  unregister)
    id="$(resolve_id "${2:-}")"
    rm -f "${REGISTRY}/${id}"
    echo "unregistered ${id}"
    ;;
  show)
    emit "$(resolve_id "${2:-}")"
    ;;
  "")
    # Hook mode. Fail open: a broken charter lookup must never block a session.
    command -v jq >/dev/null 2>&1 || exit 0
    id="$(jq -r '.session_id // empty' 2>/dev/null || true)"
    [ -n "${id}" ] && valid_id "${id}" || exit 0
    emit "${id}"
    ;;
  *)
    echo "usage: $0 [register <path> [id] | unregister [id] | show [id]]" >&2
    exit 1
    ;;
esac
