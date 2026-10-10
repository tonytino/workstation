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
