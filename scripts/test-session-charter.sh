#!/usr/bin/env bash
# Fixture-driven tests for the session-charter hook and its settings.json
# registration. Uses a temp registry; no side effects outside $TMPDIR. Exits
# non-zero if any case fails.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${ROOT}/home/dot_claude/hooks/executable_session-charter.sh"
MODIFY="${ROOT}/home/dot_claude/modify_settings.json"

command -v jq >/dev/null 2>&1 || { echo "missing dependency: jq" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/session-charter-test.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
export CLAUDE_CHARTERS_DIR="${TMP}/charters"

pass=0
fail=0
record() { # name ok
  if [ "$2" = 1 ]; then echo "PASS: $1"; pass=$((pass + 1)); else echo "FAIL: $1"; fail=$((fail + 1)); fi
}
check() { # name command...
  local name="$1"; shift
  if "$@"; then record "${name}" 1; else record "${name}" 0; fi
}
hook() { printf '%s' "$1" | bash "${HOOK}"; }

cat > "${TMP}/charter.md" <<'MD'
# Test charter
## Intent
- keep this
<!-- charter:end -->
# Reference
- drop this
MD
printf '# No marker\n- all of it\n' > "${TMP}/plain.md"

# --- registration -------------------------------------------------------------
bash "${HOOK}" register "${TMP}/charter.md" sess-1 >/dev/null
check "register writes absolute path" test "$(cat "${CLAUDE_CHARTERS_DIR}/sess-1")" = "$(cd "${TMP}" && pwd)/charter.md"
CLAUDE_CODE_SESSION_ID=sess-env bash "${HOOK}" register "${TMP}/plain.md" >/dev/null
check "register defaults to CLAUDE_CODE_SESSION_ID" test -f "${CLAUDE_CHARTERS_DIR}/sess-env"
fails() { ! "$@" >/dev/null 2>&1; }
check "register rejects missing file" fails bash "${HOOK}" register "${TMP}/nope.md" sess-x
check "register rejects path-like session id" fails bash "${HOOK}" register "${TMP}/charter.md" "../evil"

# --- hook mode ----------------------------------------------------------------
out="$(hook '{"session_id":"sess-1","source":"compact"}')"
check "registered session gets charter" grep -q "keep this" <<<"${out}"
check "stops at charter:end marker" fails grep -q "drop this" <<<"${out}"
check "includes outranks-summary instruction" grep -q "outranks the compaction summary" <<<"${out}"
check "no marker -> whole file" grep -q "all of it" <<<"$(hook '{"session_id":"sess-env"}')"
check "unregistered session -> no output" test -z "$(hook '{"session_id":"other"}')"
check "malformed input -> no output, exit 0" test -z "$(hook 'not json')"
check "empty stdin -> no output, exit 0" test -z "$(hook '')"
check "traversal session id -> no output" test -z "$(hook '{"session_id":"../sess-1"}')"
rm "${TMP}/plain.md"
check "missing charter file -> warns" grep -q "file is missing" <<<"$(hook '{"session_id":"sess-env"}')"

check "show matches hook output" test "$(bash "${HOOK}" show sess-1)" = "${out}"
bash "${HOOK}" unregister sess-1 >/dev/null
check "unregister removes entry" test ! -e "${CLAUDE_CHARTERS_DIR}/sess-1"
check "unregister keeps charter file" test -f "${TMP}/charter.md"

# --- modify_settings.json -----------------------------------------------------
run_modify() { printf '%s' "$1" | HOME=/home/u bash "${MODIFY}"; }
count_charter() { jq '[.hooks.SessionStart[]?.hooks[]? | select(.command | endswith("/session-charter.sh"))] | length' <<<"$1"; }

existing='{"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"/home/u/other.sh"}]}]}}'
out1="$(run_modify "${existing}")"
out2="$(run_modify "${out1}")"
check "settings: adds charter hook once" test "$(count_charter "${out1}")" = 1
check "settings: charter matcher is compact" test "$(jq -r '.hooks.SessionStart[-1].matcher' <<<"${out1}")" = compact
check "settings: charter path uses HOME" test "$(jq -r '.hooks.SessionStart[-1].hooks[0].command' <<<"${out1}")" = /home/u/.claude/hooks/session-charter.sh
check "settings: keeps other SessionStart hooks" test "$(jq '.hooks.SessionStart | length' <<<"${out1}")" = 2
check "settings: idempotent" test "$(jq -S . <<<"${out1}")" = "$(jq -S . <<<"${out2}")"
fresh="$(run_modify '')"
check "settings: fresh machine includes charter hook" test "$(count_charter "${fresh}")" = 1
check "settings: fresh output is a fixed point" test "$(jq -S . <<<"$(run_modify "${fresh}")")" = "$(jq -S . <<<"${fresh}")"

echo
echo "${pass} passed, ${fail} failed"
[ "${fail}" = 0 ]
