#!/usr/bin/env bash
# Claude Code PreToolUse hook: PR descriptions must open with a TL;DR section.
#
# Scope: Bash commands running `gh pr create`, or `gh pr edit` with a body flag
# (-b/--body/-F/--body-file). Everything else exits 0 fast.
#
# Passes when the first non-blank line of the body is a TL;DR heading:
# "## TL;DR", "# TL;DR", "### TL;DR", "**TL;DR**", "TL;DR:" (any case; "TLDR"
# also accepted; text may follow on the same line). Otherwise blocks (exit 2,
# reason on stderr, which Claude Code feeds back to the model). `gh pr create`
# without any body flag (e.g. --fill) is blocked too, unless it uses --web.
#
# How the body is found: the command string is tokenized with a small
# shell-word reader (single/double quotes, backslashes, $'...', heredocs,
# `;`/`&&`/`||`/`|`/newline separators), so flags inside quoted text are not
# mistaken for real ones. Body sources it understands:
#   --body/-b "<text>" | '<text>' | $'<text>' | "$(cat <<'EOF' ... EOF)"
#   --body "$(cat FILE)" / "$(< FILE)"
#   --body-file/-F FILE   (relative paths follow an earlier `cd DIR` in the command)
#   --body-file - with a heredoc, here-string or `< FILE` on the same command
# Known limits (all fail open, i.e. allow, because the body can't be read):
#   - bodies built from variables or other command substitutions, unless the
#     first non-blank line is already complete before the dynamic part
#   - --body-file pointing at a file that doesn't exist (gh will fail anyway)
#   - commands wrapped in `bash -c '...'`, eval, aliases or scripts
# One case fails closed: --body-file - (or /dev/stdin) fed by a pipe, since the
# piped text is never visible to the hook.
#
# Missing jq / unparseable input mirrors agent-attribution.sh: without jq the raw
# JSON is grepped and an in-scope command with no "TL;DR" anywhere is blocked;
# input jq can't parse, or with no tool name, exits 0.
#
# Stdin: hook JSON with tool_name and tool_input.command. See
# docs/agents/claude-hooks.md.
set -euo pipefail
# Byte-wise string indexing keeps the tokenizer fast; we only compare ASCII.
export LC_ALL=C

BLOCK_MSG='PR description must open with a TL;DR section: make the first line "## TL;DR" followed by a 1-3 sentence summary, then retry.'
NO_BODY_MSG="${BLOCK_MSG} (gh pr create was called without --body/--body-file, so there is no description to check; pass it explicitly with --body.)"
STDIN_MSG="${BLOCK_MSG} (The body comes from piped stdin, which this hook can't read; pass it with --body, a heredoc, or --body-file <path>.)"

# First non-blank line must match this (case-insensitive ERE).
TLDR_RE='^[[:space:]]*(#{1,6}[[:space:]]*)?(\*\*|__|\*|_)?[[:space:]]*TL;?DR([^[:alnum:]]|$)'
# Cheap prefilter on the raw command before tokenizing.
SCOPE_RE='gh[[:space:]]+pr[[:space:]]+(create|edit)([[:space:]]|$)'
# gh pr create/edit flags that take a value (so the value isn't read as a flag).
VALUE_FLAGS=' -a --assignee -B --base -H --head -l --label -m --milestone -p --project -r --reviewer -t --title -T --template -R --repo --recover --add-assignee --remove-assignee --add-label --remove-label --add-project --remove-project --add-reviewer --remove-reviewer '

input="$(cat)"

block() {
  printf '%s\n' "$1" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Tokenizer. Fills parallel arrays T_KIND/T_VAL/T_DYN for the string in CMD:
#   W word, S command separator, H heredoc/here-string body, I `< FILE` target,
#   O `> FILE` target. T_DYN=1 means the word contains a variable or command
#   substitution; T_VAL then holds only the static text before it.
# Inner command substitutions that aren't `cat` forms are saved in SUBS so they
# can be checked too (e.g. url=$(gh pr create ...)).
# ---------------------------------------------------------------------------
SQ="'"
Q="['\"]?"
CAT_HEREDOC_RE="^\\\$\\([[:blank:]]*cat[[:blank:]]*<<(-?)[[:blank:]]*${Q}([A-Za-z_][A-Za-z0-9_]*)${Q}[[:blank:]]*"$'\n'
CAT_FILE_RE="^\\\$\\([[:blank:]]*(cat[[:blank:]]+|<[[:blank:]]*)${Q}([^[:space:]\"')]+)${Q}[[:blank:]]*\\)"
# shellcheck disable=SC2016 # a literal $ in a regex
VAR_RE='^\$([A-Za-z_][A-Za-z0-9_]*)'

reset_word() { W_VAL=""; W_DYN=0; W_STARTED=0; }

add_text() {
  W_STARTED=1
  [ "${W_DYN}" = 1 ] || W_VAL+="$1"
}

add_dyn() { W_STARTED=1; W_DYN=1; }

push_token() { # kind value dyn
  T_KIND+=("$1")
  T_VAL+=("$2")
  T_DYN+=("$3")
}

emit_word() {
  if [ "${W_STARTED}" = 1 ]; then
    if [ "${NEXT_KIND}" = D ]; then
      PENDING_HD+=("${HD_STRIP}:${W_VAL}")
    else
      push_token "${NEXT_KIND}" "${W_VAL}" "${W_DYN}"
    fi
    NEXT_KIND=W
  fi
  reset_word
}

emit_sep() {
  emit_word
  push_token S "" 0
}

# Read one line starting at POS into LINE; POS moves past its newline.
read_line() {
  local rest="${CMD:POS}"
  LINE_START=${POS}
  if [[ "${rest}" == *$'\n'* ]]; then
    LINE="${rest%%$'\n'*}"
    POS=$((POS + ${#LINE} + 1))
  else
    LINE="${rest}"
    POS=${LEN}
  fi
}

# Is LINE the heredoc delimiter? Args: word strip(0|1). Lenient on trailing blanks.
is_delim_line() {
  local l="${LINE}"
  [ "$2" = 1 ] && l="${l#"${l%%[!$'\t']*}"}"
  l="${l%"${l##*[![:blank:]]}"}"
  [ "${l}" = "$1" ]
}

# Collect heredoc body lines from POS until the delimiter. Sets HD_BODY and
# HD_FOUND. Also accepts "WORD)" (delimiter closing a $(...)), setting HD_PAREN.
read_heredoc_body() { # word strip
  HD_BODY=""
  HD_FOUND=0
  HD_PAREN=0
  while [ "${POS}" -lt "${LEN}" ]; do
    read_line
    if is_delim_line "$1" "$2"; then
      HD_FOUND=1
      return
    fi
    if [[ "${LINE}" == "$1)"* ]]; then
      HD_FOUND=1
      HD_PAREN=1
      POS=$((LINE_START + ${#1} + 1))
      return
    fi
    HD_BODY+="${LINE}"$'\n'
  done
}

# At an unquoted newline: consume bodies of heredocs opened on that line.
read_pending_heredocs() {
  local i spec
  for ((i = 0; i < ${#PENDING_HD[@]}; i++)); do
    spec="${PENDING_HD[i]}"
    read_heredoc_body "${spec#*:}" "${spec%%:*}"
    push_token H "${HD_BODY}" 0
  done
  PENDING_HD=()
}

# POS at "(": move POS past the matching ")" (quote-aware); inner text in INNER.
skip_parens() {
  local depth=0 start=${POS} c q=""
  while [ "${POS}" -lt "${LEN}" ]; do
    c="${CMD:POS:1}"
    if [ "${q}" = "'" ]; then
      [ "${c}" != "'" ] || q=""
    elif [ "${q}" = '"' ]; then
      if [ "${c}" = "\\" ]; then POS=$((POS + 1)); elif [ "${c}" = '"' ]; then q=""; fi
    else
      case "${c}" in
        "\\") POS=$((POS + 1)) ;;
        "'" | '"') q="${c}" ;;
        '(') depth=$((depth + 1)) ;;
        ')')
          depth=$((depth - 1))
          if [ "${depth}" = 0 ]; then
            INNER="${CMD:start+1:POS-start-1}"
            POS=$((POS + 1))
            return
          fi
          ;;
      esac
    fi
    POS=$((POS + 1))
  done
  INNER="${CMD:start+1}"
}

# POS at "$(".
handle_command_subst() {
  local rest="${CMD:POS}" path
  if [[ "${rest}" =~ ${CAT_HEREDOC_RE} ]]; then
    local strip=0 word="${BASH_REMATCH[2]}"
    [ -z "${BASH_REMATCH[1]}" ] || strip=1
    POS=$((POS + ${#BASH_REMATCH[0]}))
    read_heredoc_body "${word}" "${strip}"
    if [ "${HD_FOUND}" = 0 ]; then
      add_dyn
      return
    fi
    if [ "${HD_PAREN}" = 0 ]; then
      # Skip to the ")" closing the substitution.
      while [ "${POS}" -lt "${LEN}" ] && [[ "${CMD:POS:1}" == [[:space:]] ]]; do POS=$((POS + 1)); done
      [ "${CMD:POS:1}" != ")" ] || POS=$((POS + 1))
    fi
    # $(...) strips trailing newlines, as bash would.
    local body="${HD_BODY}"
    while [[ "${body}" == *$'\n' ]]; do body="${body%$'\n'}"; done
    add_text "${body}"
    return
  fi
  if [[ "${rest}" =~ ${CAT_FILE_RE} ]]; then
    path="${BASH_REMATCH[2]}"
    POS=$((POS + ${#BASH_REMATCH[0]}))
    case "${path}" in \~/*) path="${HOME}/${path#\~/}" ;; esac
    path="$(resolve_path "${path}")"
    if [ -f "${path}" ] && [ -r "${path}" ]; then
      add_text "$(cat -- "${path}")"
    else
      add_dyn
    fi
    return
  fi
  POS=$((POS + 1))
  skip_parens
  SUBS+=("${INNER}")
  add_dyn
}

# POS at "$". Args: in_double_quotes(0|1).
handle_dollar() {
  local n="${CMD:POS+1:1}" rest content
  case "${n}" in
    '(') handle_command_subst ;;
    '{')
      rest="${CMD:POS+2}"
      content="${rest%%\}*}"
      POS=$((POS + 3 + ${#content}))
      if [ "${content}" = HOME ]; then add_text "${HOME}"; else add_dyn; fi
      ;;
    [A-Za-z_])
      rest="${CMD:POS}"
      [[ "${rest}" =~ ${VAR_RE} ]]
      POS=$((POS + ${#BASH_REMATCH[0]}))
      if [ "${BASH_REMATCH[1]}" = HOME ]; then add_text "${HOME}"; else add_dyn; fi
      ;;
    [0-9@*#?\$!-])
      POS=$((POS + 2))
      add_dyn
      ;;
    "'")
      if [ "$1" = 1 ]; then
        add_text '$'
        POS=$((POS + 1))
        return
      fi
      # $'...' (ANSI-C quoting): find the closing unescaped quote, decode escapes.
      local start=$((POS + 2))
      POS=${start}
      while [ "${POS}" -lt "${LEN}" ] && [ "${CMD:POS:1}" != "'" ]; do
        [ "${CMD:POS:1}" != "\\" ] || POS=$((POS + 1))
        POS=$((POS + 1))
      done
      content="${CMD:start:POS-start}"
      POS=$((POS + 1))
      printf -v content "%b" "${content}"
      add_text "${content}"
      ;;
    '"')
      # $"..." behaves like "..." for our purposes.
      POS=$((POS + 1))
      ;;
    *)
      add_text '$'
      POS=$((POS + 1))
      ;;
  esac
}

handle_backtick() {
  local start=$((POS + 1))
  POS=${start}
  while [ "${POS}" -lt "${LEN}" ] && [ "${CMD:POS:1}" != '`' ]; do
    [ "${CMD:POS:1}" != "\\" ] || POS=$((POS + 1))
    POS=$((POS + 1))
  done
  SUBS+=("${CMD:start:POS-start}")
  POS=$((POS + 1))
  add_dyn
}

tokenize() {
  CMD="$1"
  POS=0
  LEN=${#CMD}
  T_KIND=()
  T_VAL=()
  T_DYN=()
  PENDING_HD=()
  NEXT_KIND=W
  HD_STRIP=0
  reset_word
  local c n in_dq=0 rest run
  while [ "${POS}" -lt "${LEN}" ]; do
    c="${CMD:POS:1}"
    if [ "${in_dq}" = 1 ]; then
      case "${c}" in
        '"') in_dq=0; POS=$((POS + 1)) ;;
        "\\")
          n="${CMD:POS+1:1}"
          case "${n}" in
            '$' | '`' | '"' | "\\") add_text "${n}" ;;
            $'\n') ;;
            *) add_text "\\${n}" ;;
          esac
          POS=$((POS + 2))
          ;;
        '$') handle_dollar 1 ;;
        '`') handle_backtick ;;
        *)
          # Take the whole run of ordinary characters at once (fast on long bodies).
          rest="${CMD:POS}"
          run="${rest%%[\"\\\$\`]*}"
          add_text "${run}"
          POS=$((POS + ${#run}))
          ;;
      esac
      continue
    fi
    case "${c}" in
      ' ' | $'\t') emit_word; POS=$((POS + 1)) ;;
      $'\n')
        emit_word
        POS=$((POS + 1))
        read_pending_heredocs
        emit_sep
        ;;
      ';' | '&' | '|' | '(' | ')') emit_sep; POS=$((POS + 1)) ;;
      '<')
        emit_word
        if [ "${CMD:POS:3}" = '<<<' ]; then
          POS=$((POS + 3))
          NEXT_KIND=H
        elif [ "${CMD:POS:2}" = '<<' ]; then
          POS=$((POS + 2))
          HD_STRIP=0
          if [ "${CMD:POS:1}" = '-' ]; then HD_STRIP=1; POS=$((POS + 1)); fi
          NEXT_KIND=D
        else
          POS=$((POS + 1))
          NEXT_KIND=I
        fi
        ;;
      '>')
        emit_word
        POS=$((POS + 1))
        if [ "${CMD:POS:1}" = '&' ] || [ "${CMD:POS:1}" = '>' ]; then POS=$((POS + 1)); fi
        NEXT_KIND=O
        ;;
      "'")
        rest="${CMD:POS+1}"
        run="${rest%%"${SQ}"*}"
        add_text "${run}"
        POS=$((POS + ${#run} + 2))
        ;;
      '"') W_STARTED=1; in_dq=1; POS=$((POS + 1)) ;;
      "\\")
        n="${CMD:POS+1:1}"
        [ "${n}" = $'\n' ] || add_text "${n}"
        POS=$((POS + 2))
        ;;
      '$') handle_dollar 0 ;;
      '`') handle_backtick ;;
      '#')
        if [ "${W_STARTED}" = 1 ]; then
          add_text '#'
          POS=$((POS + 1))
        else
          # Comment: skip to (not past) the end of the line.
          while [ "${POS}" -lt "${LEN}" ] && [ "${CMD:POS:1}" != $'\n' ]; do POS=$((POS + 1)); done
        fi
        ;;
      '~')
        n="${CMD:POS+1:1}"
        if [ "${W_STARTED}" = 0 ] && { [ "${n}" = / ] || [ -z "${n}" ] || [[ "${n}" == [[:space:]] ]]; }; then
          add_text "${HOME}"
        else
          add_text '~'
        fi
        POS=$((POS + 1))
        ;;
      *) add_text "${c}"; POS=$((POS + 1)) ;;
    esac
  done
  emit_word
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

# Resolve a path against WORKDIR (tracks `cd DIR` seen earlier in the command).
resolve_path() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) printf '%s' "${WORKDIR}/$1" ;;
  esac
}

# Check body text. Args: text dyn(0|1). Returns 0 to allow; blocks otherwise.
check_body() {
  local text="$1" dyn="$2" line rest
  rest="${text}"
  while :; do
    if [[ "${rest}" == *$'\n'* ]]; then
      line="${rest%%$'\n'*}"
      rest="${rest#*$'\n'}"
      if [[ "${line}" == *[![:space:]]* ]]; then
        break
      fi
    else
      line="${rest}"
      # No newline after it: with a dynamic tail, this line isn't complete yet.
      if [ "${dyn}" = 1 ]; then return 0; fi
      if [[ "${line}" != *[![:space:]]* ]]; then block "${BLOCK_MSG}"; fi
      break
    fi
  done
  grep -qiE -- "${TLDR_RE}" <<<"${line}" || block "${BLOCK_MSG}"
}

# Check a --body-file source. Args: path dyn stdin_text stdin_kind(H|I|"").
check_body_file() {
  local path="$1" dyn="$2"
  [ "${dyn}" = 0 ] || return 0
  if [ "${path}" = "-" ] || [ "${path}" = /dev/stdin ]; then
    case "$4" in
      H) check_body "$3" 0 ;;
      I) check_body_file "$3" 0 "" "" ;;
      *) block "${STDIN_MSG}" ;;
    esac
    return 0
  fi
  path="$(resolve_path "${path}")"
  # Unreadable file: can't check; gh itself will fail on a missing file.
  [ -f "${path}" ] && [ -r "${path}" ] || return 0
  check_body "$(cat -- "${path}")" 0
}

# Check one simple command: words in CW/CD (from index 0), plus the stdin source
# (heredoc text or `<` file) seen on it.
check_simple_command() {
  local n=${#CW[@]} k=-1 i w v sub
  local body_set=0 body="" body_dyn=0 file_set=0 file="" file_dyn=0 web=0 help=0

  if [ "${n}" -ge 2 ] && [ "${CW[0]}" = cd ] && [ "${CD[1]}" = 0 ]; then
    WORKDIR="$(resolve_path "${CW[1]}")"
    return 0
  fi
  for ((i = 0; i + 2 < n; i++)); do
    w="${CW[i]}"
    if { [ "${w}" = gh ] || [[ "${w}" == */gh ]]; } && [ "${CW[i + 1]}" = pr ] &&
      { [ "${CW[i + 2]}" = create ] || [ "${CW[i + 2]}" = edit ]; }; then
      k=${i}
      break
    fi
  done
  [ "${k}" -ge 0 ] || return 0
  sub="${CW[k + 2]}"

  for ((i = k + 3; i < n; i++)); do
    w="${CW[i]}"
    case "${w}" in
      --body | -b)
        i=$((i + 1))
        [ "${i}" -lt "${n}" ] || break
        body_set=1; body="${CW[i]}"; body_dyn="${CD[i]}"
        ;;
      --body=* | -b=*) body_set=1; body="${w#*=}"; body_dyn="${CD[i]}" ;;
      --body-file | -F)
        i=$((i + 1))
        [ "${i}" -lt "${n}" ] || break
        file_set=1; file="${CW[i]}"; file_dyn="${CD[i]}"
        ;;
      --body-file=* | -F=*) file_set=1; file="${w#*=}"; file_dyn="${CD[i]}" ;;
      -b?*) body_set=1; body="${w#-b}"; body_dyn="${CD[i]}" ;;
      -F?*) file_set=1; file="${w#-F}"; file_dyn="${CD[i]}" ;;
      --web | -w) web=1 ;;
      --help | -h) help=1 ;;
      --) break ;;
      *)
        if [[ "${VALUE_FLAGS}" == *" ${w} "* ]]; then i=$((i + 1)); fi
        ;;
    esac
  done

  [ "${help}" = 0 ] || return 0
  if [ "${body_set}" = 0 ] && [ "${file_set}" = 0 ]; then
    [ "${sub}" = create ] || return 0
    [ "${web}" = 0 ] || return 0
    block "${NO_BODY_MSG}"
  fi
  if [ "${body_set}" = 1 ]; then
    check_body "${body}" "${body_dyn}"
  fi
  if [ "${file_set}" = 1 ]; then
    v=""
    [ "${STDIN_KIND}" != I ] || v="$(resolve_path "${STDIN_VAL}")"
    [ "${STDIN_KIND}" != H ] || v="${STDIN_VAL}"
    check_body_file "${file}" "${file_dyn}" "${v}" "${STDIN_KIND}"
  fi
  return 0
}

# Tokenize a command string and check every gh pr create/edit in it, including
# ones inside command substitutions.
check_command() {
  local i kind
  SUBS=()
  tokenize "$1"
  WORKDIR="${PWD}"
  CW=()
  CD=()
  STDIN_KIND=""
  STDIN_VAL=""
  for ((i = 0; i <= ${#T_KIND[@]}; i++)); do
    kind="${T_KIND[i]:-S}"
    case "${kind}" in
      W) CW+=("${T_VAL[i]}"); CD+=("${T_DYN[i]}") ;;
      H | I) STDIN_KIND="${kind}"; STDIN_VAL="${T_VAL[i]}" ;;
      S)
        # A heredoc body arrives after the newline that ends its command, so
        # look ahead for H tokens belonging to this command.
        while [ "$((i + 1))" -lt "${#T_KIND[@]}" ] && [ "${T_KIND[i + 1]}" = H ]; do
          i=$((i + 1))
          STDIN_KIND=H
          STDIN_VAL="${T_VAL[i]}"
        done
        if [ "${#CW[@]}" -gt 0 ]; then check_simple_command; fi
        CW=()
        CD=()
        STDIN_KIND=""
        STDIN_VAL=""
        ;;
    esac
  done
  for ((i = 0; i < ${#SUBS[@]}; i++)); do
    if grep -qE -- "${SCOPE_RE}" <<<"${SUBS[i]}"; then
      (check_command "${SUBS[i]}") || exit $?
    fi
  done
}

# --- Determine the tool name (jq if present, else a best-effort sed) ---------
if command -v jq >/dev/null 2>&1; then
  tool_name="$(printf '%s' "${input}" | jq -r '.tool_name // empty' 2>/dev/null || true)"
else
  tool_name="$(printf '%s' "${input}" | sed -nE 's/.*"tool_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -n1)"
fi
[ "${tool_name}" = "Bash" ] || exit 0

if ! command -v jq >/dev/null 2>&1; then
  # Without jq we can only grep the raw JSON text: block an in-scope command
  # that never mentions a TL;DR (edit only counts when it sets a body).
  grep -qE -- "${SCOPE_RE}" <<<"${input}" || exit 0
  if grep -qE 'gh[[:space:]]+pr[[:space:]]+edit' <<<"${input}" &&
    ! grep -qE '(^|[[:space:]])(-b|-F|--body|--body-file)([[:space:]=]|$)' <<<"${input}"; then
    exit 0
  fi
  grep -qE '(^|[[:space:]])(--web|-w)([[:space:]]|$)' <<<"${input}" && exit 0
  grep -qiE 'TL;?DR' <<<"${input}" ||
    block "pr-tldr hook: jq is not installed, so this command could not be parsed safely. ${BLOCK_MSG}"
  exit 0
fi

if ! cmd="$(printf '%s' "${input}" | jq -er '.tool_input.command // empty' 2>/dev/null)"; then
  cmd=""
fi
[ -n "${cmd}" ] || exit 0
grep -qE -- "${SCOPE_RE}" <<<"${cmd}" || exit 0

check_command "${cmd}"
exit 0
