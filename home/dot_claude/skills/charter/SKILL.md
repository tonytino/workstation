---
name: charter
description: Create or refresh a session charter, a doc holding the session's original intent, working preferences, decisions, open questions and status, and register it so it's re-injected into context after every compaction. Use when the user says "/charter", "make a charter for this session", "keep us on track across compactions", or wants long-running work to stay true to its original goals. Also use with "update the charter" or "unregister the charter".
---

# Session charter

A charter keeps a long session faithful to what the user actually asked for. Compaction summaries drift, and after several rounds the original goals get lost. The charter fixes that. It is a short doc in the user's own words. After every compaction, the global `SessionStart:compact` hook (`~/.claude/hooks/session-charter.sh`) re-injects it, and it outranks the summary.

## Create

1. **Settle the goals first.** Only write a charter once the session's intent is clear. If it isn't, ask instead of guessing.
2. **Draft the charter.** Use the template below and default to `CHARTER.md` in the session's working folder. If the session already has a planning or handoff doc, offer to put the charter at its top instead.
   - **Intent:** the user's goals, as close to verbatim as you can. Quote phrases. Don't paraphrase priorities into your own framing.
   - **Working preferences:** the rules that shape how to work, from the user's CLAUDE.md files, memory, and anything they said in this session. Keep only what applies to this work.
   - **Decisions log:** every decision so far. Give each a date and say who made it (the user, or you with the user's agreement).
   - **Open questions:** each with an owner and where it was asked (ticket, thread or doc).
   - **Current status:** what's done, what's in flight, and the next step.
3. **Show the draft and get an explicit yes.** The charter is the user's statement of intent, so they approve it. Don't write it until they do.
4. **Write the file and register it:**
   ```bash
   ~/.claude/hooks/session-charter.sh register <charter-path>
   ```
   The session ID defaults to `$CLAUDE_CODE_SESSION_ID`. If that's unset, find the ID another way (for example the scratchpad path or the session's transcript file name), confirm it with the user, and pass it as the second argument.
5. **Prove the hook works:** run `~/.claude/hooks/session-charter.sh show` and check that it prints the charter section. If `~/.claude/settings.json` has no `SessionStart` entry with matcher `compact` running `session-charter.sh`, tell the user to run `chezmoi apply`.

## Template

Everything above the `<!-- charter:end -->` line is injected after compaction, so keep that part short. Reference material can go below the marker.

```markdown
# <Project> — session charter

> **For Claude, after any compaction:** this charter outranks the compaction summary. If they disagree, the charter wins. If the charter looks stale, say so and ask the user. Re-read this whole file before acting.
>
> **Recency rule:** update the Decisions log and Current status whenever a decision lands, a ticket or PR changes state, or a step finishes, before replying to the user. Before the user runs `/compact`, bring Current status fully up to date. Never rewrite Intent or Working preferences without the user's explicit say-so.

## Intent (the user's words, near-verbatim)
- ...

## Working preferences
- ...

## Decisions log
| Date | Decision | By |
|---|---|---|

## Open questions
| Question | Owner | Where asked |
|---|---|---|

## Current status (update me)
_As of YYYY-MM-DD._
- ...
- **Next step:** ...

<!-- charter:end -->

# Reference
...
```

## Keep it current

Follow the recency rule for the rest of the session. Edit the charter in place: never touch Intent or Working preferences without the user's say-so, and always keep Decisions log, Open questions and Current status fresh. When the user says they're about to compact, update Current status first.

## After a compaction

The hook output arrives at the start of the next turn. Re-read the full charter file. Check the compaction summary against it, and where they conflict, follow the charter and say so in one line.

## Unregister

When the work is done, or the user asks:

```bash
~/.claude/hooks/session-charter.sh unregister
```

Unregistering leaves the charter file in place. Only delete it if the user asks.
