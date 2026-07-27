# claude-status

A tiny, self-contained [Claude Code](https://claude.com/claude-code) statusline that shows your model/context on line 1 and — crucially — your **spend against a monthly cap** on line 2, including **today** and the **rolling 7-day** total.

It's a single Bash script. No plugin, no marketplace, no daemon.

```
Opus 4.8 (1M) medium    |  claude-status (main) 2f +14 -3
██░░░░░░░░ 21% 1M       |  💰 $209/$500 41% ⇣46% · 1d $4 · 7d $61
```

## What it shows

**Line 1** — `model (context) effort | project (branch) Nf +A -D`
- Model name + context-window size, current effort level (from the session or `effortLevel` in settings)
- Project name, git branch, and diff stats (`N` files, `+` added / `-` deleted lines). Worktree-aware.

**Line 2** — `context-bar PCT% CTX | 💰 $month/$cap pct% pace · 1d $today · 7d $week`
- Context-usage bar, color-coded (green <70%, yellow ≥70%, red ≥90%)
- `$month/$cap` — this calendar month's spend vs your cap (colored by % of cap)
- `pct%` — percent of cap used
- `pace` — `⇡N%` over pace (red, overspending) / `⇣N%` under pace (green, surplus), vs how far through the month you are
- `1d $today` — today's spend so far
- `7d $week` — rolling 7-day spend

## Requirements

- [Claude Code](https://claude.com/claude-code)
- [`jq`](https://jqlang.github.io/jq/) — `brew install jq` / `apt install jq`
- [`bun`](https://bun.sh) (for `bunx`) **or** Node.js (for `npx`) — used to run `ccusage` on demand; nothing is installed globally
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
| `CLAUDE_MONTHLY_CAP` | `500` | Monthly spend cap in USD. Set lower than your real cap for an early-warning buffer. |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | _(unset)_ | If set, the context bar measures distance to auto-compaction instead of the full window. |

Example:

```json
{
  "env": { "CLAUDE_MONTHLY_CAP": "400" },
  "statusLine": { "type": "command", "command": "~/.claude/statusbar.sh" }
}
```

## How it works

- On every render the script reads Claude Code's statusline JSON (stdin) + your `settings.json` in one `jq` call, draws line 1 and the context bar, and reads git status directly (`--no-optional-locks`, read-only).
- Cost is **cached**. The script prints the last cached value instantly and, when the cache is older than ~10 min, kicks off a **background** `ccusage daily --mode calculate --json` refresh (rate-limited by an atomic `mkdir` lock so only one runs at a time). Rendering never blocks on `ccusage`.
- Cache lives in `${XDG_RUNTIME_DIR:-~/.cache}/claude-status/cost-cache.json` (user-owned dir only; never shared `/tmp`).
- First render after install shows `💰 computing…` until the first background refresh lands.

## Uninstall

```sh
./install.sh --uninstall   # removes the statusLine key and the script
rm -rf ~/.cache/claude-status
```

Or just delete the `statusLine` block from `~/.claude/settings.json`.

## Credit

Line-1 layout and the context-bar/auto-compact logic are adapted from [claude-pace](https://github.com/Astro-Han/claude-pace). The cost-vs-cap tracking is the addition here.

## License

MIT — see [LICENSE](LICENSE).
