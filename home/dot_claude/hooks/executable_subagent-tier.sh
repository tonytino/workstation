#!/usr/bin/env bash
# Claude Code PreToolUse hook: subagents must run on a model below the
# orchestrator's tier.
#
# Fires on the subagent tool (Agent, or Task in older Claude Code). Blocks
# (exit 2, reason on stderr, which Claude Code feeds back to the model) when
# tool_input.model is missing (the subagent would inherit the session's model)
# or is at or above the session's tier. Tiers: haiku < sonnet < opus < fable
# (mythos counts as fable).
#
# The hook input doesn't carry the session's model, so it is read from the
# transcript: the newest main-thread assistant entry's message.model. Anything
# it can't determine fails open (exit 0): this hook must never block every
# subagent because of a parsing problem. See docs/agents/claude-hooks.md.
set -euo pipefail
# GREP_OPTIONS=--color=always would wrap matches in escape codes and break the
# JSON we pipe from grep into jq.
unset GREP_OPTIONS GREP_COLOR GREP_COLORS

# Bytes of transcript tail to scan, smallest first. Transcripts can be hundreds
# of MB; the newest assistant entry is almost always in the first window.
TAIL_WINDOWS=(1048576 16777216)

input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

# One jq pass over the hook input. Each field on its own line; read -r tolerates
# empty values.
fields="$(printf '%s' "${input}" | jq -r '
  [ (.tool_name // ""), (.agent_id // ""), (.transcript_path // ""),
    (.tool_input.subagent_type // ""), (.tool_input.model // "") ]
  | map(if type == "string" then gsub("[\r\n]"; " ") else tostring end)
  | .[]' 2>/dev/null)" || exit 0
{
  IFS= read -r tool_name || true
  IFS= read -r agent_id || true
  IFS= read -r transcript || true
  IFS= read -r subagent_type || true
  IFS= read -r model || true
} <<<"${fields}"

case "${tool_name}" in
  Agent | Task) ;;
  *) exit 0 ;;
esac

# Rule 1: fired inside a subagent. Only the main session is enforced for now.
[ -z "${agent_id}" ] || exit 0

# Rule 2: forks always run on the session's model and ignore `model`.
[ "${subagent_type}" != "fork" ] || exit 0

# Echo a tier number for a model name or id (0 = unknown).
tier_of() {
  local m
  m="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "${m}" in
    *mythos* | *fable*) echo 4 ;;
    *opus*) echo 3 ;;
    *sonnet*) echo 2 ;;
    *haiku*) echo 1 ;;
    *) echo 0 ;;
  esac
}

tier_name() {
  case "$1" in
    4) echo fable ;;
    3) echo opus ;;
    2) echo sonnet ;;
    1) echo haiku ;;
  esac
}

# Newest main-thread assistant model in the transcript, or nothing.
session_model() {
  local path="$1" size window found
  [ -n "${path}" ] && [ -f "${path}" ] && [ -r "${path}" ] || return 0
  size="$(wc -c <"${path}" | tr -d '[:space:]')"
  for window in "${TAIL_WINDOWS[@]}"; do
    # The first line of a tail window may be cut mid-entry; fromjson? drops it.
    # grep pre-filters so jq only parses assistant lines.
    found="$(tail -c "${window}" -- "${path}" 2>/dev/null |
      grep -F '"assistant"' |
      jq -Rr 'fromjson?
        | select(.type == "assistant" and (.isSidechain // false) != true)
        | .message.model? // empty
        | select(type == "string" and length > 0 and (startswith("<") | not))' 2>/dev/null |
      tail -n 1 || true)"
    if [ -n "${found}" ]; then
      printf '%s' "${found}"
      return 0
    fi
    [ "${size}" -gt "${window}" ] || return 0
  done
}

# Rule 3: unknown session model -> fail open.
session_tier="$(tier_of "$(session_model "${transcript}")")"
[ "${session_tier}" -gt 0 ] || exit 0

# Rule 4: nothing is below haiku.
[ "${session_tier}" -gt 1 ] || exit 0

allowed=""
for ((t = session_tier - 1; t >= 1; t--)); do
  allowed="${allowed:+${allowed}, }$(tier_name "${t}")"
done
block() {
  printf 'Subagents must run below your tier (you are %s): set model to one of: %s, then retry. Forks are exempt.\n' \
    "$(tier_name "${session_tier}")" "${allowed}" >&2
  exit 2
}

# Rule 5: no model means the subagent inherits the session's tier.
[ -n "${model}" ] || block

# Rule 6: unknown requested model -> allow; same tier or above -> block.
model_tier="$(tier_of "${model}")"
[ "${model_tier}" -gt 0 ] || exit 0
[ "${model_tier}" -lt "${session_tier}" ] || block
exit 0
