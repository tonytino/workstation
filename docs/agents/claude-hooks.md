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
