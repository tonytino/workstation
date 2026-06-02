# Neovim Primer

A primer keyed to the config in `home/dot_config/nvim/init.lua`. For a senior
engineer who already knows what an editor is and just wants to be productive
in Vim within a week.

## 7-Day plan

**Day 0 (one sitting, ~30 min):** Run `vimtutor` from any terminal. It is the
only tutorial worth doing first.

**Day 1:** Use Neovim for your next 3 git commits. Goal: `i` to insert, `Esc`
to leave insert mode, `:wq` to save and quit. Nothing else.

**Day 2:** Same, plus `dd` (delete line) and `u` (undo).

**Day 3:** Edit a real config file (e.g. `~/.zshrc`). Practice `j k`,
`/word` then `n` to find next match. Make one change, save.

**Day 4:** Add `*` (search the word under the cursor) and `:%s/old/new/g`
(global replace). Replace one thing in a commit body or a config.

**Day 5:** Open `~/.config/nvim/init.lua`. Use `<C-h/j/k/l>` to move between
splits, `<Space>ff` to fuzzy-find files, `<Space>fg` to grep. Read code; do
not edit yet.

**Day 6:** Edit your config. Use `>>` / `<<` (indent / dedent), `gcc`
(comment toggle), `gd` (LSP go-to-definition). Make a small tweak.

**Day 7:** Commit your changes from inside Neovim. You are now fluent enough
to keep using it in your normal workflow.

Hands will hurt for the first few days. By day 7, the muscle memory is there.

## The 20 commands that matter

| Command | What it does |
|---|---|
| `h j k l` (or arrow keys) | Cursor left / down / up / right |
| `w` / `b` | Forward / back one word |
| `gg` / `G` | Top / bottom of file |
| `42G` | Jump to line 42 |
| `i` / `a` | Insert before / after the cursor |
| `o` / `O` | New line below / above, then insert |
| `dd` / `yy` / `p` | Delete line / yank line / paste |
| `u` / `<C-r>` | Undo / redo |
| `/foo` then `n` | Search for `foo`, then next match |
| `*` | Search for the word under the cursor |
| `:%s/old/new/g` | Replace `old` with `new` in the whole file |
| `>>` / `<<` | Indent / dedent the current line |
| `:w` / `:q` / `:wq` | Save / quit / save and quit |
| `:q!` | Quit without saving (the panic button) |
| `Esc` | Back to Normal mode (or, in this config, clears search highlight) |

That covers ~80% of daily editing.

**Arrow keys work everywhere.** `hjkl` is just the home-row equivalent — your
fingers eventually want it because the home row is faster, but arrow keys
are fully supported in every mode and compose with verbs the same way
(`d→` deletes the next character, etc.). No rush.

## Modes

| Mode | How you enter it | What it does |
|---|---|---|
| **Normal** | `Esc` | Default. Move, delete, copy, paste. Where commands live. |
| **Insert** | `i`, `a`, `o`, `O` | Type text. Cursor is blinking. |
| **Visual** | `v` (char), `V` (line), `<C-v>` (block) | Select text, then verb to act on it. |
| **Command** | `:` | Type a command, hit `Enter`. `Esc` cancels. |

Stuck? Press `Esc` twice. You are always one Esc away from Normal.

## The grammar that makes Vim click

Vim commands are **verb + motion**. Once you internalize this, you stop
memorizing and start composing.

- **Verbs:** `d` delete, `c` change, `y` yank, `>` indent, `<` dedent
- **Motions:** `w` word, `b` back-word, `e` end-of-word, `t` until-char,
  `f` find-char, `i` inside, `a` around, `p` paragraph
- **Modifiers:** numbers (`5j` = 5 down), and visual selection (`v` then verb)

Examples:

- `dw` — delete a word
- `d5w` — delete 5 words
- `dt.` — delete up to the next period
- `ci"` — change inside double quotes (replace string contents)
- `yap` — yank a paragraph
- `>ip` — indent inside the paragraph
- `=G` — auto-indent from cursor to end of file

## Your config's keymaps

Leader is **Space**. These are bindings from `init.lua`:

| Keys | Action |
|---|---|
| `<Space>w` | Save |
| `<Space>q` | Quit |
| `<Space>ff` | Telescope: find files |
| `<Space>fg` | Telescope: live grep across project |
| `<Space>fb` | Telescope: open buffers |
| `<Space>fh` | Telescope: search help |
| `<C-h/j/k/l>` | Move between split windows |
| `Esc` | Clear search highlight |
| `gcc` | Comment / uncomment current line (Comment.nvim) |
| `gc` (visual) | Comment / uncomment selection |
| `K` | LSP: hover docs for symbol under cursor |
| `gd` | LSP: go to definition |

Inside Telescope: `<C-x>` opens in horizontal split, `<C-v>` in vertical
split, `<C-t>` in a new tab.

## Telescope is the superpower

`<Space>ff` and `<Space>fg` replace `Cmd+P` and `Cmd+Shift+F` from VS Code.
Get fluent with these two and Vim immediately feels productive.

- **`<Space>ff`** — fuzzy filename search. Type partial substrings, no need
  for exact spelling.
- **`<Space>fg`** — ripgrep across the whole project. Live preview of every
  match in context.

Get comfortable with fuzzy matching: `aurutls` matches `Auth/UserList.tsx`.

## Escape hatches

Things break. Here is how to bail:

- `:q!` — quit without saving
- `u` — undo. Press it as many times as needed.
- `:e!` — reload current file from disk, discarding all unsaved changes
- `:set number` — show line numbers if your gutter is empty for some reason
- `:!bash` — drop into a shell; type `exit` to come back

If you "broke" the editor, it's almost always either a leftover mode (Esc),
a stale search highlight (Esc clears it via this config), or unsaved changes
(`:q!` to bail).

## Resources

- **vimtutor** — bundled with vim/nvim. Run it. The only required reading.
- **`:help <topic>`** — built-in docs. `:help w`, `:help :s`, `:help telescope`.
- **vim-cheatsheet.com** — keep a tab open during week 1.
- **Vim Adventures** (vim-adventures.com) — gamified learning if you stall.
- **The config itself** — `~/.config/nvim/init.lua` is short and readable.
  Use `K` / `gd` to explore unfamiliar Lua APIs.
