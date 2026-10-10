#!/usr/bin/env bash
# Fixture-driven tests for the agent-attribution hook and its settings.json
# registration. Pipes JSON into the hook and asserts exit codes. No side effects
# outside $TMPDIR. Exits non-zero if any case fails.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${ROOT}/home/dot_claude/hooks/executable_agent-attribution.sh"
MODIFY="${ROOT}/home/dot_claude/modify_settings.json"

command -v jq >/dev/null 2>&1 || { echo "missing dependency: jq" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-attribution-test.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

pass=0
fail=0

record() { # name ok
  if [ "$2" = 1 ]; then
    echo "PASS: $1"
    pass=$((pass + 1))
  else
    echo "FAIL: $1"
    fail=$((fail + 1))
  fi
}

# expect_exit <expected-code> <name> <json>
expect_exit() {
  local want="$1" name="$2" json="$3" got=0
  printf '%s' "${json}" | bash "${HOOK}" >/dev/null 2>"${TMP}/stderr" || got=$?
  if [ "${got}" = "${want}" ]; then
    record "${name}" 1
  else
    record "${name} (want exit ${want}, got ${got})" 0
  fi
}

bash_json() { jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}'; }
mcp_json() { jq -n --arg n "$1" --arg t "$2" '{tool_name: $n, tool_input: {text: $t, nested: {items: [$t]}}}'; }

STRAIGHT="🤖 Anthony's Agent"
CURLY="🤖 Anthony’s Agent"

# --- Bash: in-scope commands --------------------------------------------------
bash_cases=(
  "gh pr create --title t --body"
  "gh pr comment 12 --body"
  "gh pr review 12 --comment --body"
  "gh issue create --title t --body"
  "gh issue comment 3 --body"
  "gh api repos/o/r/issues/3/comments -f body"
  "gh api repos/o/r/pulls/3/reviews -X POST -f body"
  "linear create --title t --description"
  "linear issue create --title t --description"
  "linear comment ISP-1 --body"
)
for base in "${bash_cases[@]}"; do
  expect_exit 2 "block (no marker): ${base%% --*}" "$(bash_json "${base} 'hello'")"
  expect_exit 0 "allow (straight): ${base%% --*}" "$(bash_json "${base} 'hello
${STRAIGHT}'")"
  expect_exit 0 "allow (curly): ${base%% --*}" "$(bash_json "${base} 'hello
${CURLY}'")"
done

# Block message is exactly what Claude should see.
msg="$(printf '%s' "$(bash_json "gh pr create --body x")" | bash "${HOOK}" 2>&1 >/dev/null || true)"
want_msg="Agent attribution required: append a final line \"${STRAIGHT}\" to the content you are posting, then retry."
if [ "${msg}" = "${want_msg}" ]; then record "block message text" 1; else record "block message text" 0; fi

# --- Bash: out of scope -------------------------------------------------------
for cmd in \
  "git status" \
  "gh pr view 12" \
  "gh pr edit 12 --body x" \
  "gh issue edit 3 --body x" \
  "gh pr review 12 --approve" \
  "gh api repos/o/r/issues/3/comments" \
  "gh api repos/o/r/issues/3/comments -X GET" \
  "gh api repos/o/r/issues/3/comments --method GET -f per_page=5" \
  "linear issue list" \
  "ls -la"; do
  expect_exit 0 "allow out-of-scope: ${cmd}" "$(bash_json "${cmd}")"
done

# --- Bash: --body-file --------------------------------------------------------
printf 'body\n%s\n' "${STRAIGHT}" >"${TMP}/with.md"
printf 'body without footer\n' >"${TMP}/without.md"
expect_exit 0 "body-file with marker" "$(bash_json "gh pr create --title t --body-file ${TMP}/with.md")"
expect_exit 2 "body-file without marker" "$(bash_json "gh pr create --title t --body-file ${TMP}/without.md")"
expect_exit 0 "body-file=with marker" "$(bash_json "gh pr create --title t --body-file=${TMP}/with.md")"
expect_exit 2 "body-file=without marker" "$(bash_json "gh pr create --title t --body-file=${TMP}/without.md")"
expect_exit 0 "-F file with marker" "$(bash_json "gh issue create --title t -F ${TMP}/with.md")"
expect_exit 2 "-F file without marker" "$(bash_json "gh issue create --title t -F ${TMP}/without.md")"
expect_exit 2 "missing body-file, no marker" "$(bash_json "gh pr create --body-file ${TMP}/nope.md")"
expect_exit 0 "body-file stdin with heredoc marker" "$(bash_json "gh pr create --body-file - <<'EOF'
text
${STRAIGHT}
EOF")"
expect_exit 2 "body-file stdin heredoc without marker" "$(bash_json "gh pr create --body-file - <<'EOF'
text
EOF")"
# gh api -F is a field flag, not a body file: marker in a file must not count.
expect_exit 2 "gh api -F is not a body file" "$(bash_json "gh api repos/o/r/issues/3/comments -F body=@${TMP}/with.md")"

# gh pr review with body vs bare approve
expect_exit 2 "gh pr review --approve with body, no marker" "$(bash_json "gh pr review 1 --approve --body 'lgtm'")"
expect_exit 0 "gh pr review --approve with body and marker" "$(bash_json "gh pr review 1 --approve --body 'lgtm ${STRAIGHT}'")"
expect_exit 0 "gh pr review --approve (no body)" "$(bash_json "gh pr review 1 --approve")"

# --- MCP tools ----------------------------------------------------------------
mcp_blocked=(
  mcp__abc-123__slack_send_message
  mcp__abc-123__slack_send_message_draft
  mcp__abc-123__slack_schedule_message
  mcp__abc-123__slack_create_canvas
  mcp__abc-123__send_message
  mcp__abc-123__reply
  mcp__abc-123__forward
  mcp__abc-123__create_draft
  mcp__abc-123__notion-create-pages
  mcp__abc-123__notion-create-comment
  mcp__abc-123__create_file
  mcp__abc-123__create_event
  mcp__abc-123__create
  mcp__abc-123__batch
  mcp__abc-123__create_issue
  mcp__abc-123__save_comment
)
for tool in "${mcp_blocked[@]}"; do
  expect_exit 2 "block (no marker): ${tool}" "$(mcp_json "${tool}" "hello")"
  expect_exit 0 "allow (straight): ${tool}" "$(mcp_json "${tool}" "hello ${STRAIGHT}")"
  expect_exit 0 "allow (curly): ${tool}" "$(mcp_json "${tool}" "hello ${CURLY}")"
done

for tool in \
  mcp__x__slack_read_channel \
  mcp__x__notion-fetch \
  mcp__x__list_events \
  mcp__ccd_session__mark_chapter \
  mcp__ccd_session__create \
  mcp__Claude_Browser__batch \
  mcp__context7__create \
  mcp__playwright__create \
  mcp__terminal__send_message \
  mcp__scheduled-tasks__create \
  mcp__visualize__create \
  mcp__claude-in-chrome__create \
  Read \
  Edit; do
  expect_exit 0 "allow out-of-scope: ${tool}" "$(mcp_json "${tool}" "hello")"
done

# Fail-closed / fail-open edges.
expect_exit 0 "no tool name -> allow" '{"foo":1}'
expect_exit 0 "empty stdin -> allow" ''
expect_exit 2 "in-scope tool with non-object tool_input -> block" '{"tool_name":"mcp__x__slack_send_message","tool_input":"oops"}'

# --- modify_settings.json -----------------------------------------------------
existing='{"foo":1,"hooks":{"PreToolUse":[{"matcher":"","hooks":[{"type":"command","command":"/home/u/.claude/hooks/peon-ping/peon.sh"}]}],"Stop":[{"hooks":[]}]}}'
run_modify() { printf '%s' "$1" | HOME=/home/u bash "${MODIFY}"; }

count_hook() { jq '[.hooks.PreToolUse[]?.hooks[]? | select(.command | endswith("/agent-attribution.sh"))] | length' <<<"$1"; }

out1="$(run_modify "${existing}")"
out2="$(run_modify "${out1}")"

if [ "$(jq '[.hooks.PreToolUse[]?.hooks[]? | select(.command | contains("peon-ping"))] | length' <<<"${out1}")" = 1 ]; then record "settings: keeps peon-ping" 1; else record "settings: keeps peon-ping" 0; fi
if [ "$(count_hook "${out1}")" = 1 ]; then record "settings: adds hook once" 1; else record "settings: adds hook once" 0; fi
if [ "$(jq -r '.hooks.PreToolUse[-1].hooks[0].command' <<<"${out1}")" = "/home/u/.claude/hooks/agent-attribution.sh" ]; then record "settings: hook path uses HOME" 1; else record "settings: hook path uses HOME" 0; fi
if [ "$(jq -r '.attribution.pr' <<<"${out1}")" = "${STRAIGHT}" ]; then record "settings: attribution.pr set" 1; else record "settings: attribution.pr set" 0; fi
if [ "$(jq -r '.foo' <<<"${out1}")" = 1 ] && [ "$(jq '.hooks.Stop | length' <<<"${out1}")" = 1 ]; then record "settings: preserves unrelated keys" 1; else record "settings: preserves unrelated keys" 0; fi
if [ "$(jq -S . <<<"${out1}")" = "$(jq -S . <<<"${out2}")" ]; then record "settings: idempotent on second run" 1; else record "settings: idempotent on second run" 0; fi

fresh="$(run_modify '')"
if [ "$(count_hook "${fresh}")" = 1 ] && [ "$(jq -r '.attribution.pr' <<<"${fresh}")" = "${STRAIGHT}" ]; then record "settings: empty stdin includes hook + attribution" 1; else record "settings: empty stdin includes hook + attribution" 0; fi
if [ "$(jq -S . <<<"$(run_modify "${fresh}")")" = "$(jq -S . <<<"${fresh}")" ]; then record "settings: fresh output is a fixed point" 1; else record "settings: fresh output is a fixed point" 0; fi

echo
echo "${pass} passed, ${fail} failed"
[ "${fail}" = 0 ]
