# claude-status

A tiny, self-contained [Claude Code](https://claude.com/claude-code) statusline that renders a **bordered two-section panel**: your repo/branch on top, and your model, context usage, and **spend** — this session, Pi, Claude, and the combined month against a cap — below.

It's a single Bash script. No plugin, no marketplace, no daemon.

```
╭─ REPO ────────────────────────────────────────────────────────────────────╮
│ claude-status  main 2f +55 -31                                            │
├─ SESSION ──────────────────────────────────────────────────────────────────┤
│ Opus 4.8 (1M) medium │  ██░░░░░░░░ 22% of 1M │ 💰 session $12 · pi $7 · claude $25 · total $32/$300 │
╰────────────────────────────────────────────────────────────────────────────╯
```

The panel auto-sizes to its widest row, so every line and border stays aligned. Borders and section titles are plain white; the `` and `` are [Nerd Font](https://www.nerdfonts.com/) icons.

## What it shows

**`REPO`** — `<folder>  <branch> Nf +A -D`
- Project folder name
- Git branch (magenta, with a `` branch icon) and diff stats: `N` files, `+` added / `-` deleted lines. Worktree-aware.
- When not in a git repo, just the folder name.

**`SESSION`** — `model (context) effort │ <gauge> context-bar PCT% of CTX │ 💰 …`
- Model name + context-window size, and current effort level (from the session, or `effortLevel` in settings)
- A `` gauge + context-usage bar, color-coded green <70% / yellow ≥70% / red ≥90%, with `PCT% of <size>`
- **Cost**, left to right:
  - `session $session` — this Claude session's spend (Claude Code's own tally; exact, matches `/usage`)
  - `pi $month` — this calendar month's Pi spend from Pi session records
  - `claude $month` — this calendar month's Claude spend from `ccusage`
  - `total $month/$cap` — combined monthly spend vs your cap, colored by % of cap

## Requirements

- [Claude Code](https://claude.com/claude-code)
- A [Nerd Font](https://www.nerdfonts.com/) in your terminal (e.g. **Hack Nerd Font Mono**) for the branch/gauge icons
- [`jq`](https://jqlang.github.io/jq/) — `brew install jq` / `apt install jq`
- [`bun`](https://bun.sh) (for `bunx`) **or** Node.js (for `npx`) — used to run `ccusage` on demand for the Claude monthly figure; nothing is installed globally
- Bash 3.2+ (macOS default is fine)

## Install

```sh
git clone https://github.com/abeltramo/claude-status.git
cd claude-status
./install.sh
```

`install.sh` copies `statusbar.sh` to `~/.claude/statusbar.sh`, makes it executable, and points `statusLine` in `~/.claude/settings.json` at it (creating/merging the key with `jq`).

Then **restart Claude Code** (or start a new session).

### Develop against the repo (symlink)

If you keep the clone around, use `--link` to symlink instead of copy, so edits to the repo file are live immediately (one source of truth):

```sh
./install.sh --link
```

### Manual install

Copy the script and wire it up yourself:

```sh
cp statusbar.sh ~/.claude/statusbar.sh
chmod +x ~/.claude/statusbar.sh
```

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusbar.sh"
  }
}
```

## Configuration

Set via environment variables (e.g. in the `env` block of `~/.claude/settings.json`):

| Variable | Default | Meaning |
|---|---|---|
| `CLAUDE_MONTHLY_CAP` | `300` | Combined monthly spend cap in USD. Set lower than your real cap for an early-warning buffer. |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | _(unset)_ | If set, the context bar measures distance to auto-compaction instead of the full window. |

Example:

```json
{
  "env": { "CLAUDE_MONTHLY_CAP": "400" },
  "statusLine": { "type": "command", "command": "~/.claude/statusbar.sh" }
}
```

## How it works

- On every render the script reads Claude Code's statusline JSON (stdin) + your `settings.json` in one `jq` call, then draws the bordered panel. Row widths are measured with ANSI stripped (via `sed`) so the box aligns even with colors, the money emoji, and Nerd Font glyphs.
- **Session cost** comes straight from the stdin payload (`cost.total_cost_usd`) — Claude Code's own figure, so it's exact and matches `/usage`, with no price table to maintain. It's populated even on Vertex/Bedrock, where the raw transcripts carry no per-message cost.
- **Pi / Claude month totals** are **cached**. The script prints the last cached values instantly and, when the cache is older than ~10 min, starts a **background** refresh. The refresh uses `ccusage daily --mode calculate --json` for Claude and Pi session records for Pi. Rendering never blocks on either source.
- Cost is computed from token counts via `ccusage` (`--mode calculate`) for Claude and recorded Pi usage for Pi, so those figures are **estimates**, not your invoice.
- Git status is read directly (`--no-optional-locks`, read-only).
- Cache lives in `${XDG_RUNTIME_DIR:-~/.cache}/claude-status/cost-cache.json` (user-owned dir only; never shared `/tmp`).
- First render after install shows `💰 $session · computing…` until the first background refresh lands.

## Uninstall

```sh
./install.sh --uninstall   # removes the statusLine key and the script
rm -rf ~/.cache/claude-status
```

Or just delete the `statusLine` block from `~/.claude/settings.json`.

## Credit

The context-bar/auto-compact logic and the idea of reading session cost from the stdin payload are adapted from [claude-pace](https://github.com/Astro-Han/claude-pace). The bordered panel, git/repo section, Nerd Font icons, and the combined Pi/Claude monthly cost tracking are the additions here.

## License

MIT — see [LICENSE](LICENSE).
