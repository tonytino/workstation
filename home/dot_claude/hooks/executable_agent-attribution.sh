#!/usr/bin/env bash
# Claude Code PreToolUse hook: require the agent footer on outward-facing content.
#
# Blocks (exit 2, reason on stderr, which Claude Code feeds back to the model)
# any NEW content Claude creates on the user's behalf (PR/issue creates and
# comments, reviews with a body, Linear creates/comments, Slack/Gmail/Notion/
# Drive/Calendar/Docs MCP writes) unless it contains the marker below.
# Edits/updates are intentionally not checked. Everything else exits 0 fast.
#
# Stdin: hook JSON with tool_name and tool_input. See docs/agents/claude-hooks.md.
set -euo pipefail

MARKER_STRAIGHT="🤖 Anthony's Agent"
MARKER_CURLY="🤖 Anthony’s Agent"
BLOCK_MSG="Agent attribution required: append a final line \"${MARKER_STRAIGHT}\" to the content you are posting, then retry."

# Generic MCP tool names only apply to MCP servers that are not Claude Code's own.
EXCLUDED_MCP='^mcp__(ccd_|Claude_|context7__|playwright__|claude-in-chrome__|terminal__|scheduled-tasks__|visualize__)'
SPECIFIC_SUFFIX='^(slack_send_message|slack_send_message_draft|slack_schedule_message|slack_create_canvas|notion-create-pages|notion-create-comment|create_issue|create_comment|save_issue|save_comment)$'
GENERIC_SUFFIX='^(send_message|reply|forward|create_draft|create_file|create_event|create|batch)$'

input="$(cat)"

block() {
  printf '%s\n' "$1" >&2
  exit 2
}

has_marker() {
  grep -qF -- "${MARKER_STRAIGHT}" <<<"$1" || grep -qF -- "${MARKER_CURLY}" <<<"$1"
}

# Is this tool in scope by name alone? Args: tool_name. Echoes bash|mcp|none.
classify_tool() {
  local name="$1" suffix
  if [ "${name}" = "Bash" ]; then
    echo bash
    return
  fi
  case "${name}" in
    mcp__*) ;;
    *) echo none; return ;;
  esac
  suffix="${name##*__}"
  if grep -qE "${SPECIFIC_SUFFIX}" <<<"${suffix}"; then
    echo mcp
  elif grep -qE "${GENERIC_SUFFIX}" <<<"${suffix}" &&
    ! grep -qE "${EXCLUDED_MCP}" <<<"${name}"; then
    echo mcp
  else
    echo none
  fi
}

# Does a Bash command create new outward-facing content? Args: command.
bash_in_scope() {
  local cmd="$1"
  if grep -qE 'gh[[:space:]]+(pr|issue)[[:space:]]+(create|comment)([[:space:]]|$)' <<<"${cmd}"; then
    return 0
  fi
  # Reviews only count when they carry a body (a bare --approve is fine).
  if grep -qE 'gh[[:space:]]+pr[[:space:]]+review([[:space:]]|$)' <<<"${cmd}" &&
    grep -qE '(^|[[:space:]])(-b|-F|--body|--body-file)([[:space:]=]|$)' <<<"${cmd}"; then
    return 0
  fi
  # gh api writing to comment/review/reply endpoints: needs an explicit write
  # method or field flags (which make gh default to POST), and not an explicit GET.
  if grep -qE 'gh[[:space:]]+api([[:space:]]|$)' <<<"${cmd}" &&
    grep -qE '(comments|reviews|replies)' <<<"${cmd}" &&
    ! grep -qiE '(-X|--method)[[:space:]=]*GET' <<<"${cmd}" &&
    grep -qE '((-X|--method)[[:space:]=]*(POST|PUT|PATCH)|[[:space:]](-f|-F|--field|--raw-field|--input)([[:space:]=]|$))' <<<"${cmd}"; then
    return 0
  fi
  if grep -qE '(^|[^[:alnum:]_/.-])linear[[:space:]]+(issue[[:space:]]+)?(create|comment)([[:space:]]|$)' <<<"${cmd}"; then
    return 0
  fi
  return 1
}

# Echo the text of any --body-file/-F file referenced by a gh pr/issue command.
body_file_contents() {
  local cmd="$1" token path
  grep -qE 'gh[[:space:]]+(pr|issue)[[:space:]]' <<<"${cmd}" || return 0
  while IFS= read -r token; do
    path="$(printf '%s' "${token}" | sed -E 's/^(--body-file|-F)[[:space:]=]+//')"
    path="${path#[\"\']}"
    path="${path%[\"\']}"
    # "-" means stdin; the heredoc is already part of the command string.
    if [ -n "${path}" ] && [ "${path}" != "-" ] && [ -f "${path}" ]; then
      cat -- "${path}"
      printf '\n'
    fi
  done < <(grep -oE '(--body-file|-F)[[:space:]=]+[^[:space:]]+' <<<"${cmd}" || true)
}

# --- Determine the tool name (jq if present, else a best-effort sed) ---------
if command -v jq >/dev/null 2>&1; then
  tool_name="$(printf '%s' "${input}" | jq -r '.tool_name // empty' 2>/dev/null || true)"
else
  tool_name="$(printf '%s' "${input}" | sed -nE 's/.*"tool_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -n1)"
fi

# Can't tell what tool this is: don't interfere.
[ -n "${tool_name}" ] || exit 0

kind="$(classify_tool "${tool_name}")"
[ "${kind}" != "none" ] || exit 0

# --- In scope by name: from here on, fail closed -----------------------------
if ! command -v jq >/dev/null 2>&1; then
  if [ "${kind}" = "bash" ]; then
    # Without jq we can only check the raw JSON text for in-scope commands.
    if bash_in_scope "${input}" && ! has_marker "${input}"; then
      block "agent-attribution hook: jq is not installed, so this command could not be parsed safely. ${BLOCK_MSG}"
    fi
    exit 0
  fi
  block "agent-attribution hook: jq is not installed, so ${tool_name} could not be checked. Install jq (brew install jq) and retry."
fi

if [ "${kind}" = "bash" ]; then
  if ! cmd="$(printf '%s' "${input}" | jq -er '.tool_input.command // empty' 2>/dev/null)"; then
    cmd=""
  fi
  [ -n "${cmd}" ] || exit 0
  bash_in_scope "${cmd}" || exit 0
  text="${cmd}"$'\n'"$(body_file_contents "${cmd}")"
  has_marker "${text}" || block "${BLOCK_MSG}"
  exit 0
fi

# MCP: marker may be in any string value anywhere in tool_input.
if ! text="$(printf '%s' "${input}" | jq -er '[.tool_input | .. | strings] | join("\n")' 2>/dev/null)"; then
  block "agent-attribution hook: could not parse tool input for ${tool_name}. ${BLOCK_MSG}"
fi
has_marker "${text}" || block "${BLOCK_MSG}"
exit 0
