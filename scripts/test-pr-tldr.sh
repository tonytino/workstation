#!/usr/bin/env bash
# Fixture-driven tests for the pr-tldr hook and its settings.json registration.
# Pipes JSON into the hook and asserts exit codes. No side effects outside
# $TMPDIR. Exits non-zero if any case fails.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${ROOT}/home/dot_claude/hooks/executable_pr-tldr.sh"
MODIFY="${ROOT}/home/dot_claude/modify_settings.json"

command -v jq >/dev/null 2>&1 || { echo "missing dependency: jq" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-tldr-test.XXXXXX")"
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
allow() { expect_exit 0 "allow: $1" "$(bash_json "$2")"; }
deny() { expect_exit 2 "block: $1" "$(bash_json "$2")"; }

# --- --body: heredoc and quoted forms ------------------------------------------
allow "heredoc body, TL;DR first" "gh pr create --title t --body \"\$(cat <<'EOF'
## TL;DR
Adds a thing.

## Details
more
EOF
)\""
deny "heredoc body, no TL;DR" "gh pr create --title t --body \"\$(cat <<'EOF'
## Summary
Adds a thing.
EOF
)\""
allow "heredoc body, blank lines before TL;DR" "gh pr create --title t --body \"\$(cat <<'EOF'


## TL;DR
x
EOF
)\""
allow "heredoc <<-EOF with tab-indented delimiter" "gh pr create --title t --body \"\$(cat <<-EOF
	## TL;DR
	x
	EOF
)\""
allow "heredoc with EOF) on one line" "gh pr create --title t --body \"\$(cat <<'EOF'
## TL;DR
x
EOF)\""
allow "double-quoted body, TL;DR first" 'gh pr create --title "t" --body "## TL;DR
Adds a thing."'
allow "single-quoted body, TL;DR first" "gh pr create --title t --body '## TL;DR
Adds a thing.'"
allow "ANSI-C quoted body" "gh pr create --title t --body \$'## TL;DR\nAdds a thing.'"
allow "--body= form" "gh pr create --title t --body='## TL;DR
x'"
allow "-b short form" "gh pr create -t t -b '## TL;DR
x'"
deny "double-quoted body, no TL;DR" 'gh pr create --title t --body "Adds a thing."'
deny "single-quoted body, no TL;DR" "gh pr create --title t --body 'Adds a thing.'"
deny "empty body" "gh pr create --title t --body ''"
deny "-b short form, no TL;DR" "gh pr create -t t -b 'Adds a thing.'"

# --- Accepted heading forms -----------------------------------------------------
for heading in "## TL;DR" "# TL;DR" "### TL;DR" "**TL;DR**" "TL;DR:" "tl;dr:" "## TLDR" "## tl;dr" "**TL;DR:** Adds a thing." "TL;DR: Adds a thing."; do
  allow "heading form '${heading}'" "gh pr create --title t --body '${heading}
Adds a thing.'"
done
for heading in "TL;DRx" "## Summary TL;DR" "> TL;DR" "TLDRs"; do
  deny "not a heading '${heading}'" "gh pr create --title t --body '${heading}
x'"
done

# --- TL;DR present but not first --------------------------------------------------
deny "TL;DR not first (heredoc)" "gh pr create --title t --body \"\$(cat <<'EOF'
## Summary
x

## TL;DR
y
EOF
)\""
deny "TL;DR not first (quoted)" "gh pr create --title t --body 'Intro
## TL;DR
y'"
deny "TL;DR only in title" "gh pr create --title 'TL;DR' --body 'no summary'"

# Block message is exactly what Claude should see.
want_msg='PR description must open with a TL;DR section: make the first line "## TL;DR" followed by a 1-3 sentence summary, then retry.'
msg="$(printf '%s' "$(bash_json "gh pr create --title t --body x")" | bash "${HOOK}" 2>&1 >/dev/null || true)"
if [ "${msg}" = "${want_msg}" ]; then record "block message text" 1; else record "block message text" 0; fi

# --- --body-file ---------------------------------------------------------------
printf '## TL;DR\nAdds a thing.\n' >"${TMP}/good.md"
printf '\n\n**TL;DR**\nAdds a thing.\n' >"${TMP}/good-bold.md"
printf '## Summary\nAdds a thing.\n' >"${TMP}/bad.md"
mkdir -p "${TMP}/sub"
cp "${TMP}/good.md" "${TMP}/sub/rel-good.md"
cp "${TMP}/bad.md" "${TMP}/sub/rel-bad.md"
allow "--body-file pass" "gh pr create --title t --body-file ${TMP}/good.md"
allow "--body-file pass (blank lines, bold)" "gh pr create --title t --body-file ${TMP}/good-bold.md"
deny "--body-file fail" "gh pr create --title t --body-file ${TMP}/bad.md"
allow "--body-file= pass" "gh pr create --title t --body-file=${TMP}/good.md"
deny "--body-file= fail" "gh pr create --title t --body-file=${TMP}/bad.md"
allow "-F pass" "gh pr create --title t -F '${TMP}/good.md'"
deny "-F fail" "gh pr create --title t -F \"${TMP}/bad.md\""
allow "relative --body-file after cd (pass)" "cd ${TMP}/sub && gh pr create --title t --body-file rel-good.md"
deny "relative --body-file after cd (fail)" "cd ${TMP}/sub && gh pr create --title t --body-file rel-bad.md"
allow "--body-file missing file (can't check)" "gh pr create --title t --body-file ${TMP}/nope.md"
allow "--body \$(cat file) pass" "gh pr create --title t --body \"\$(cat ${TMP}/good.md)\""
deny "--body \$(cat file) fail" "gh pr create --title t --body \"\$(cat ${TMP}/bad.md)\""

# --- stdin bodies ---------------------------------------------------------------
deny "--body-file - from a pipe" "printf '## TL;DR\nx' | gh pr create --title t --body-file -"
deny "-F /dev/stdin from a pipe" "cat ${TMP}/good.md | gh pr create --title t -F /dev/stdin"
allow "--body-file - with heredoc, TL;DR first" "gh pr create --title t --body-file - <<'EOF'
## TL;DR
x
EOF"
deny "--body-file - with heredoc, no TL;DR" "gh pr create --title t --body-file - <<'EOF'
Summary
EOF"
allow "--body-file - with here-string" "gh pr create --title t --body-file - <<< '## TL;DR
x'"
deny "--body-file - with here-string, no TL;DR" "gh pr create --title t --body-file - <<< 'Summary'"
allow "--body-file - < good file" "gh pr create --title t --body-file - < ${TMP}/good.md"
deny "--body-file - < bad file" "gh pr create --title t --body-file - < ${TMP}/bad.md"

# --- No body / --fill / --web ----------------------------------------------------
deny "gh pr create --fill" "gh pr create --fill"
deny "gh pr create --fill-first" "gh pr create --fill-first --base main"
deny "gh pr create title only" "gh pr create --title t"
allow "gh pr create --web" "gh pr create --web"
allow "gh pr create --fill --web" "gh pr create --fill --web"
allow "gh pr create -w" "gh pr create -w --title t"
allow "gh pr create --help" "gh pr create --help"

# --- gh pr edit -------------------------------------------------------------------
allow "gh pr edit without body" "gh pr edit 12 --title 'new title' --add-label bug"
allow "gh pr edit with good body" "gh pr edit 12 --body '## TL;DR
x'"
deny "gh pr edit with bad body" "gh pr edit 12 --body 'Summary'"
deny "gh pr edit with bad body-file" "gh pr edit 12 --body-file ${TMP}/bad.md"

# --- Compound commands and dynamic bodies ------------------------------------------
deny "after git push &&" "git push -u origin HEAD && gh pr create --title t --body 'x'"
allow "after git push && (good)" "git push -u origin HEAD && gh pr create --title t --body '## TL;DR
x'"
deny "inside \$(...) assignment" "url=\$(gh pr create --title t --body 'x') && echo \"\${url}\""
allow "inside \$(...) assignment (good)" "url=\$(gh pr create --title t --body '## TL;DR
x') && echo \"\${url}\""
# shellcheck disable=SC2016 # literal $VARs are the fixture
allow "body from a variable (can't check)" 'gh pr create --title t --body "$BODY"'
# shellcheck disable=SC2016
allow "variable after complete TL;DR line" 'gh pr create --title t --body "## TL;DR
$SUMMARY"'
# shellcheck disable=SC2016
deny "variable after complete non-TL;DR line" 'gh pr create --title t --body "Summary
$SUMMARY"'
allow "--title value that looks like a flag" "gh pr create --title '--body' --body '## TL;DR
x'"
deny "flag-like text inside quoted title is ignored" "gh pr create --title \"use --web\" --body 'x'"
allow "path-qualified gh" "/opt/homebrew/bin/gh pr create --title t --body '## TL;DR
x'"

# --- Out of scope ---------------------------------------------------------------------
for cmd in \
  "git status" \
  "gh pr view 12" \
  "gh pr list" \
  "gh pr comment 12 --body x" \
  "gh issue create --title t --body x" \
  "echo 'gh pr create --body x'" \
  "git commit -m \"\$(cat <<'EOF'
docs: mention gh pr create --fill
EOF
)\"" \
  "ls -la"; do
  allow "out-of-scope: ${cmd%%$'\n'*}" "${cmd}"
done
for tool in Read Edit Write mcp__x__create_issue; do
  expect_exit 0 "allow non-Bash tool: ${tool}" "$(jq -n --arg n "${tool}" '{tool_name: $n, tool_input: {command: "gh pr create --fill"}}')"
done

# Fail-open edges.
expect_exit 0 "no tool name -> allow" '{"foo":1}'
expect_exit 0 "empty stdin -> allow" ''
expect_exit 0 "Bash with non-object tool_input -> allow" '{"tool_name":"Bash","tool_input":"oops"}'

# Without jq: grep the raw JSON (fails closed on an in-scope command with no TL;DR).
NOJQ="${TMP}/nojq-bin"
mkdir -p "${NOJQ}"
for bin in bash cat grep sed head; do ln -sf "$(command -v "${bin}")" "${NOJQ}/${bin}"; done
nojq_expect() { # want name json
  local got=0
  printf '%s' "$3" | PATH="${NOJQ}" bash "${HOOK}" >/dev/null 2>&1 || got=$?
  if [ "${got}" = "$1" ]; then record "no jq: $2" 1; else record "no jq: $2 (want exit $1, got ${got})" 0; fi
}
nojq_expect 2 "block without TL;DR" "$(bash_json "gh pr create --title t --body x")"
nojq_expect 0 "allow with TL;DR" "$(bash_json "gh pr create --title t --body '## TL;DR
x'")"
nojq_expect 0 "allow out of scope" "$(bash_json "git status")"
nojq_expect 0 "allow gh pr edit without body" "$(bash_json "gh pr edit 3 --title t")"

# --- modify_settings.json -----------------------------------------------------------
existing='{"foo":1,"hooks":{"PreToolUse":[{"matcher":"","hooks":[{"type":"command","command":"/home/u/.claude/hooks/peon-ping/peon.sh"}]}],"Stop":[{"hooks":[]}]}}'
run_modify() { printf '%s' "$1" | HOME=/home/u bash "${MODIFY}"; }

count_hook() { jq '[.hooks.PreToolUse[]?.hooks[]? | select(.command | endswith("/pr-tldr.sh"))] | length' <<<"$1"; }
pr_entry() { jq -c '[.hooks.PreToolUse[] | select(any(.hooks[]; .command | endswith("/pr-tldr.sh")))][0]' <<<"$1"; }

out1="$(run_modify "${existing}")"
out2="$(run_modify "${out1}")"

if [ "$(jq '[.hooks.PreToolUse[]?.hooks[]? | select(.command | contains("peon-ping"))] | length' <<<"${out1}")" = 1 ]; then record "settings: keeps peon-ping" 1; else record "settings: keeps peon-ping" 0; fi
if [ "$(jq '[.hooks.PreToolUse[]?.hooks[]? | select(.command | endswith("/agent-attribution.sh"))] | length' <<<"${out1}")" = 1 ]; then record "settings: keeps agent-attribution" 1; else record "settings: keeps agent-attribution" 0; fi
if [ "$(count_hook "${out1}")" = 1 ]; then record "settings: adds hook once" 1; else record "settings: adds hook once" 0; fi
want_entry='{"matcher":"Bash","hooks":[{"type":"command","command":"/home/u/.claude/hooks/pr-tldr.sh","timeout":10}]}'
if [ "$(pr_entry "${out1}")" = "${want_entry}" ]; then record "settings: entry shape (matcher Bash, HOME path, timeout 10)" 1; else record "settings: entry shape" 0; fi
if [ "$(jq -r '.foo' <<<"${out1}")" = 1 ] && [ "$(jq '.hooks.Stop | length' <<<"${out1}")" = 1 ]; then record "settings: preserves unrelated keys" 1; else record "settings: preserves unrelated keys" 0; fi
if [ "$(jq -S . <<<"${out1}")" = "$(jq -S . <<<"${out2}")" ]; then record "settings: idempotent on second run" 1; else record "settings: idempotent on second run" 0; fi

fresh="$(run_modify '')"
if [ "$(count_hook "${fresh}")" = 1 ] && [ "$(pr_entry "${fresh}")" = "${want_entry}" ]; then record "settings: fresh machine includes hook" 1; else record "settings: fresh machine includes hook" 0; fi
if [ "$(jq -S . <<<"$(run_modify "${fresh}")")" = "$(jq -S . <<<"${fresh}")" ]; then record "settings: fresh output is a fixed point" 1; else record "settings: fresh output is a fixed point" 0; fi

echo
echo "${pass} passed, ${fail} failed"
[ "${fail}" = 0 ]
