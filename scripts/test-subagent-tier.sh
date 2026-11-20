#!/usr/bin/env bash
# Fixture-driven tests for the subagent-tier hook and its settings.json
# registration. Builds synthetic transcripts in a temp dir, pipes hook JSON in
# and asserts exit codes. No side effects outside $TMPDIR. Exits non-zero if any
# case fails.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${ROOT}/home/dot_claude/hooks/executable_subagent-tier.sh"
MODIFY="${ROOT}/home/dot_claude/modify_settings.json"

command -v jq >/dev/null 2>&1 || { echo "missing dependency: jq" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/subagent-tier-test.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

pass=0
fail=0
record() { # name ok
  if [ "$2" = 1 ]; then echo "PASS: $1"; pass=$((pass + 1)); else echo "FAIL: $1"; fail=$((fail + 1)); fi
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

# Synthetic transcript lines.
user_line() { jq -nc '{type: "user", isSidechain: false, message: {role: "user", content: "hi"}}'; }
asst_line() { # model [isSidechain]
  jq -nc --arg m "$1" --argjson s "${2:-false}" \
    '{type: "assistant", isSidechain: $s, message: {role: "assistant", model: $m, content: []}}'
}
other_line() { jq -nc '{type: "system", isSidechain: false, content: "assistant mentioned here"}'; }

# transcript <name> <model>: main-thread history ending on <model>.
transcript() {
  local path="${TMP}/$1.jsonl"
  {
    user_line
    asst_line claude-haiku-4-5
    user_line
    asst_line "$2"
    other_line
  } >"${path}"
  printf '%s' "${path}"
}

# hook_json <transcript> <model or ""> [subagent_type] [agent_id] [tool_name]
hook_json() {
  jq -nc --arg t "$1" --arg m "$2" --arg st "${3:-general-purpose}" --arg aid "${4:-}" --arg tn "${5:-Agent}" '
    {tool_name: $tn, session_id: "s-1", transcript_path: $t,
     tool_input: ({description: "d", prompt: "p", subagent_type: $st}
                  + (if $m == "" then {} else {model: $m} end))}
    + (if $aid == "" then {} else {agent_id: $aid} end)'
}

# --- Rule matrix by session tier ---------------------------------------------
# session-model | allowed models | blocked models
matrix=(
  "claude-fable-5-2|opus sonnet haiku|fable"
  "claude-mythos-1|opus sonnet haiku|fable"
  "claude-opus-5-5|sonnet haiku|opus fable"
  "claude-sonnet-4-6|haiku|sonnet opus fable"
)
for row in "${matrix[@]}"; do
  IFS='|' read -r sess allow deny <<<"${row}"
  t="$(transcript "${sess}" "${sess}")"
  for m in ${allow}; do expect_exit 0 "${sess}: allow ${m}" "$(hook_json "${t}" "${m}")"; done
  for m in ${deny}; do expect_exit 2 "${sess}: block ${m}" "$(hook_json "${t}" "${m}")"; done
  expect_exit 2 "${sess}: block missing model" "$(hook_json "${t}" "")"
  expect_exit 0 "${sess}: allow unknown model" "$(hook_json "${t}" "gpt-x")"
  expect_exit 0 "${sess}: allow fork without model" "$(hook_json "${t}" "" fork)"
  expect_exit 0 "${sess}: allow fork with same model" "$(hook_json "${t}" fable fork)"
  expect_exit 0 "${sess}: allow inside subagent (agent_id)" "$(hook_json "${t}" "" general-purpose agent-123)"
  expect_exit 0 "${sess}: Task tool, lower model" "$(hook_json "${t}" haiku general-purpose "" Task)"
done

t="$(transcript haiku claude-haiku-4-5)"
expect_exit 0 "haiku session: allow haiku" "$(hook_json "${t}" haiku)"
expect_exit 0 "haiku session: allow missing model" "$(hook_json "${t}" "")"
expect_exit 0 "haiku session: allow opus (nothing below haiku)" "$(hook_json "${t}" opus)"

# Full model ids and case are matched by substring.
t="$(transcript opus-ids claude-opus-5-5)"
expect_exit 2 "full id: claude-opus-5-5 blocked under opus" "$(hook_json "${t}" claude-opus-5-5)"
expect_exit 0 "full id: claude-sonnet-4-6 allowed under opus" "$(hook_json "${t}" claude-sonnet-4-6)"
expect_exit 0 "full id: Claude-Haiku-4-5 (mixed case) allowed" "$(hook_json "${t}" Claude-Haiku-4-5)"
expect_exit 2 "full id: claude-mythos-1 blocked under opus" "$(hook_json "${t}" claude-mythos-1)"
expect_exit 2 "Task tool: missing model blocked" "$(hook_json "${t}" "" general-purpose "" Task)"

# Block message names the tier and the allowed models.
msg="$(printf '%s' "$(hook_json "${t}" "")" | bash "${HOOK}" 2>&1 >/dev/null || true)"
want="Subagents must run below your tier (you are opus): set model to one of: sonnet, haiku, then retry. Forks are exempt."
if [ "${msg}" = "${want}" ]; then record "block message text" 1; else record "block message text: got '${msg}'" 0; fi
t="$(transcript fable-msg claude-fable-5-2)"
msg="$(printf '%s' "$(hook_json "${t}" fable)" | bash "${HOOK}" 2>&1 >/dev/null || true)"
if grep -qF "(you are fable): set model to one of: opus, sonnet, haiku," <<<"${msg}"; then record "fable message lists opus, sonnet, haiku" 1; else record "fable message lists opus, sonnet, haiku" 0; fi

# --- Session model detection --------------------------------------------------
# Sidechain entries after the main thread's last assistant entry are skipped.
side="${TMP}/sidechain.jsonl"
{ user_line; asst_line claude-sonnet-4-6; asst_line claude-fable-5-2 true; asst_line claude-fable-5-2 true; } >"${side}"
expect_exit 2 "sidechain skipped: session is sonnet, sonnet blocked" "$(hook_json "${side}" sonnet)"
expect_exit 0 "sidechain skipped: haiku allowed under sonnet" "$(hook_json "${side}" haiku)"
expect_exit 2 "sidechain skipped: opus blocked under sonnet" "$(hook_json "${side}" opus)"

# Synthetic <synthetic> entries are skipped.
synth="${TMP}/synthetic.jsonl"
{ asst_line claude-opus-5-5; asst_line '<synthetic>'; } >"${synth}"
expect_exit 2 "<synthetic> skipped: session stays opus" "$(hook_json "${synth}" opus)"

# Model switch mid-session: the newest entry wins.
sw="${TMP}/switch.jsonl"
{ asst_line claude-fable-5-2; user_line; asst_line claude-sonnet-4-6; } >"${sw}"
expect_exit 2 "model switch: newest (sonnet) wins" "$(hook_json "${sw}" opus)"

# Newest assistant entry beyond the first 1 MiB tail window is still found.
far="${TMP}/far.jsonl"
{
  asst_line claude-opus-5-5
  pad="$(head -c 600000 /dev/zero | tr '\0' 'x')"
  jq -nc --arg p "${pad}" '{type: "user", isSidechain: false, message: {role: "user", content: $p}}'
  jq -nc --arg p "${pad}" '{type: "user", isSidechain: false, message: {role: "user", content: $p}}'
} >"${far}"
expect_exit 2 "assistant entry outside 1 MiB window still found" "$(hook_json "${far}" opus)"

# Fail open when the session model can't be determined.
expect_exit 0 "missing transcript -> allow" "$(hook_json "${TMP}/nope.jsonl" "")"
expect_exit 0 "empty transcript_path -> allow" "$(hook_json "" "")"
printf 'not json\n{"type":"assistant"\n' >"${TMP}/garbage.jsonl"
expect_exit 0 "unparseable transcript -> allow" "$(hook_json "${TMP}/garbage.jsonl" "")"
{ user_line; user_line; } >"${TMP}/noasst.jsonl"
expect_exit 0 "no assistant entries -> allow" "$(hook_json "${TMP}/noasst.jsonl" "")"
t="$(transcript unknown some-other-model)"
expect_exit 0 "unknown session model -> allow" "$(hook_json "${t}" "")"
{ asst_line claude-opus-5-5 true; } >"${TMP}/onlyside.jsonl"
expect_exit 0 "only sidechain entries -> allow" "$(hook_json "${TMP}/onlyside.jsonl" "")"

# GREP_OPTIONS coloring must not break detection.
t="$(transcript grepopts claude-opus-5-5)"
got=0
printf '%s' "$(hook_json "${t}" "")" | GREP_OPTIONS=--color=always bash "${HOOK}" >/dev/null 2>&1 || got=$?
if [ "${got}" = 2 ]; then record "GREP_OPTIONS=--color=always still blocks" 1; else record "GREP_OPTIONS=--color=always still blocks (got ${got})" 0; fi

# --- Unrelated tools and bad input -------------------------------------------
t="$(transcript unrelated claude-opus-5-5)"
for tool in Bash Read Edit mcp__x__create Agents TaskStop; do
  expect_exit 0 "unrelated tool: ${tool}" "$(hook_json "${t}" "" general-purpose "" "${tool}")"
done
expect_exit 0 "empty stdin -> allow" ''
expect_exit 0 "non-JSON stdin -> allow" 'not json'
expect_exit 0 "no tool name -> allow" '{"foo":1}'

# --- modify_settings.json -----------------------------------------------------
existing='{"foo":1,"hooks":{"PreToolUse":[{"matcher":"","hooks":[{"type":"command","command":"/home/u/.claude/hooks/peon-ping/peon.sh"}]}],"Stop":[{"hooks":[]}]}}'
run_modify() { printf '%s' "$1" | HOME=/home/u bash "${MODIFY}"; }
count_tier() { jq '[.hooks.PreToolUse[]? | select(.matcher == "Agent|Task") | .hooks[]? | select(.command == "/home/u/.claude/hooks/subagent-tier.sh" and .timeout == 10)] | length' <<<"$1"; }
check() { # name command...
  local name="$1"; shift
  if "$@"; then record "${name}" 1; else record "${name}" 0; fi
}

out1="$(run_modify "${existing}")"
out2="$(run_modify "${out1}")"
check "settings: adds tier hook once" test "$(count_tier "${out1}")" = 1
check "settings: keeps peon-ping" test "$(jq '[.hooks.PreToolUse[]?.hooks[]? | select(.command | contains("peon-ping"))] | length' <<<"${out1}")" = 1
check "settings: keeps agent-attribution" test "$(jq '[.hooks.PreToolUse[]?.hooks[]? | select(.command | endswith("/agent-attribution.sh"))] | length' <<<"${out1}")" = 1
check "settings: preserves unrelated keys" test "$(jq -c '[.foo, (.hooks.Stop | length)]' <<<"${out1}")" = "[1,1]"
check "settings: idempotent on second run" test "$(jq -S . <<<"${out1}")" = "$(jq -S . <<<"${out2}")"

fresh="$(run_modify '')"
check "settings: fresh machine includes tier hook" test "$(count_tier "${fresh}")" = 1
check "settings: fresh output is a fixed point" test "$(jq -S . <<<"$(run_modify "${fresh}")")" = "$(jq -S . <<<"${fresh}")"

echo
echo "${pass} passed, ${fail} failed"
[ "${fail}" = 0 ]
