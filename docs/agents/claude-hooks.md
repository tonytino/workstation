# Claude Code hooks

Hook scripts live under `home/dot_claude/hooks/` and render to `~/.claude/hooks/` (use the `executable_` prefix so they're runnable). They are registered in `~/.claude/settings.json` by `home/dot_claude/modify_settings.json`.

## agent-attribution

`hooks/executable_agent-attribution.sh` is a `PreToolUse` hook that blocks outward-facing content Claude creates on the user's behalf unless it contains the footer marker:

```
🤖 Anthony's Agent
```

Either a straight `'` or curly `’` apostrophe is accepted. On a miss the hook exits 2 with a stderr message telling Claude to append the marker and retry (exit 2 + stderr is how `PreToolUse` hooks block and feed the reason back to the model).

### Scope

Only NEW content is checked (creates, posts, comments, replies, sends, drafts). Edits and updates are not.

- **Bash:** `gh pr create|comment`, `gh issue create|comment`, `gh pr review` (only with `-b/--body/-F/--body-file`; a bare `--approve` is allowed), `gh api` writes (POST/PUT/PATCH or field flags) to `comments|reviews|replies` paths (not when `-X GET`/`--method GET`), and `linear [issue] create|comment`. The marker may be in the command string (including heredocs) or in a file given via `--body-file`/`-F` on `gh pr`/`gh issue` commands. For `gh api`, `-F` is a field flag, not a file.
- **MCP tools:** matched by the part of the tool name after the last `__` (server IDs are opaque UUIDs): Slack send/draft/schedule/canvas, Gmail send/reply/forward/draft, Notion create page/comment, Drive `create_file`, Calendar `create_event`, Claude Docs `create`/`batch`, Linear create/save issue/comment. Generic names are ignored for Claude Code's own servers (`mcp__ccd_*`, `mcp__Claude_*`, `context7`, `playwright`, `claude-in-chrome`, `terminal`, `scheduled-tasks`, `visualize`). The marker may be in any string anywhere in `tool_input`.
- Everything else exits 0 immediately.
- If `jq` is missing or the input can't be parsed for an in-scope tool, the hook fails closed (exit 2). If it can't determine the tool name at all, it exits 0.

### Registration

`modify_settings.json` deliberately does not put hooks in `MANAGED`: its merge replaces arrays, which would clobber other `hooks.PreToolUse` entries (e.g. peon-ping). Instead, after the merge it appends one `PreToolUse` entry (matcher `Bash|mcp__.*`, command `$HOME/.claude/hooks/agent-attribution.sh`, timeout 10) only if no existing entry already runs `*/agent-attribution.sh`, so repeated applies are idempotent. The fresh-machine branch emits the entry too; the no-`jq` passthrough branch is unchanged.

`MANAGED` also sets `attribution.pr` to the marker so Claude Code's built-in PR attribution uses it.

### Testing

```
scripts/test-agent-attribution.sh
```

Pipes fixture JSON into the hook, asserts exit codes per surface (blocked, allowed with each apostrophe, out-of-scope, `--body-file`), and checks the `modify_settings.json` merge (keeps existing hooks, adds once, idempotent, fresh machine). Prints PASS/FAIL per case; non-zero exit on any failure. ShellCheck (CI scans the whole repo) must also pass.

## session-charter

`hooks/executable_session-charter.sh` is a `SessionStart` hook (matcher `compact`). After every compaction, it re-injects a session's **charter** into context: a short doc holding the user's original intent, working preferences, decisions log, open questions and status. Repeated compaction summaries drift, and the charter keeps long sessions true to what was asked. The `/charter` skill (`home/dot_claude/skills/charter/SKILL.md`) drafts the charter with the user and registers it.

### How it works

- **Registry:** `~/.claude/charters/<session_id>` is a one-line file holding the charter's absolute path. `CLAUDE_CHARTERS_DIR` overrides the directory, which the tests use.
- **Hook mode (no args):** reads the hook JSON from stdin.
  - If the session is registered, it prints an instruction (the charter outranks the summary; re-read the file) plus the charter up to a `<!-- charter:end -->` line, or the whole file if there's no marker.
  - Unregistered sessions, bad input, a session id that isn't `[A-Za-z0-9_-]+`, or missing `jq` all produce no output and exit 0. It fails open, because it must never block a session.
  - A registered but missing charter file prints a warning instead.
- **CLI mode:**
  - `register <path> [session-id]`
  - `unregister [session-id]`
  - `show [session-id]`, which prints exactly what the hook would inject.
  - The session id defaults to `$CLAUDE_CODE_SESSION_ID`.

### Registration

Same pattern as agent-attribution. After the merge, `modify_settings.json` appends one `SessionStart` entry (matcher `compact`, command `$HOME/.claude/hooks/session-charter.sh`, timeout 10), but only if no existing entry already runs `*/session-charter.sh`. The fresh-machine branch emits it too.

### Testing

```
scripts/test-session-charter.sh
```

Covers register/unregister/show, the end marker, unregistered and malformed input, path-traversal ids, a missing charter file, and the `modify_settings.json` merge (adds once, keeps other `SessionStart` hooks, idempotent, fresh machine).

## subagent-tier

`hooks/executable_subagent-tier.sh` is a `PreToolUse` hook (matcher `Agent|Task`: the subagent tool is `Agent` in current Claude Code and `Task` in older versions). It enforces "subagents always run on a model below the orchestrator's tier".

Tiers, lowest to highest: haiku (1) < sonnet (2) < opus (3) < fable (4). A model id containing `mythos` also counts as tier 4. Names match by case-insensitive substring, so full ids like `claude-opus-5-5` work.

### Rules (in order)

1. `agent_id` present (the hook fired inside a subagent): allow. Only the main session is enforced for now.
2. `tool_input.subagent_type` is `fork`: allow. Forks always run on the session's model and ignore `model`.
3. Session model can't be determined (no transcript, unreadable, no matching entry, unknown model): allow. It fails open, because a parsing problem must never block every subagent.
4. Session is haiku: allow. Nothing is below it.
5. `tool_input.model` absent or empty: block. The subagent would inherit the session's model.
6. `tool_input.model` unknown: allow. Known and at or above the session's tier: block. Otherwise allow.

A block exits 2 with a stderr message naming the session tier and the allowed models, e.g. `Subagents must run below your tier (you are opus): set model to one of: sonnet, haiku, then retry. Forks are exempt.` Unrelated tools, missing `jq` and unparseable input all exit 0.

### How the session model is found

The hook input doesn't include the session's model, so the hook reads the transcript at `transcript_path` (JSONL). It takes the newest entry with `type == "assistant"` and `isSidechain` not `true`, and uses its `message.model`. It skips `<synthetic>` placeholders. It reads only the last 1 MiB of the file, then the last 16 MiB if nothing matched. It pre-filters lines with `grep` before `jq`, and unsets `GREP_OPTIONS`/`GREP_COLOR(S)` so colored grep output can't corrupt the JSON. On a 159 MB transcript the hook takes about 75 ms.

### Limits

- The model comes from the transcript, not live session state. After a `/model` switch, the hook goes by the last model that actually replied. The first spawn of a session, before any assistant entry is written, isn't enforced.
- Nested subagents (`agent_id` set) aren't enforced.
- The transcript format is internal to Claude Code. If its field names change, the hook fails open rather than blocking.

### Registration

Same pattern as agent-attribution. After the merge, `modify_settings.json` appends one `PreToolUse` entry (matcher `Agent|Task`, command `$HOME/.claude/hooks/subagent-tier.sh`, timeout 10), but only if no existing entry already runs `*/subagent-tier.sh`. The fresh-machine branch emits it too.

### Testing

```
scripts/test-subagent-tier.sh
```

Builds synthetic transcripts in a temp dir. It covers the rule matrix for fable, mythos, opus, sonnet and haiku sessions, full and mixed-case model ids, the block message, sidechain and `<synthetic>` entries being skipped, a mid-session model switch, an entry outside the first tail window, fail-open cases (missing, unparseable or assistant-less transcript, unknown model), `GREP_OPTIONS=--color=always`, unrelated tools, and the `modify_settings.json` merge (adds once, keeps other hooks, idempotent, fresh machine).
