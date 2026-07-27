#!/usr/bin/env bash
# Installer for claude-status: copies statusbar.sh into ~/.claude and points the
# statusLine key in ~/.claude/settings.json at it. Idempotent; safe to re-run.
#
#   ./install.sh              install / update
#   ./install.sh --uninstall  remove the statusLine key and the installed script
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.claude/statusbar.sh"
SETTINGS="$HOME/.claude/settings.json"

command -v jq >/dev/null || { echo "error: jq is required (brew install jq / apt install jq)"; exit 1; }
mkdir -p "$HOME/.claude"

# Ensure settings.json exists and is valid JSON before we edit it.
_ensure_settings() {
  [ -f "$SETTINGS" ] || echo '{}' >"$SETTINGS"
  jq -e . "$SETTINGS" >/dev/null 2>&1 || { echo "error: $SETTINGS is not valid JSON; fix it first"; exit 1; }
}

# Merge a jq filter into settings.json atomically.
_edit_settings() {
  local tmp
  tmp="$(mktemp "${SETTINGS%/*}/.claude-status-XXXXXX")"
  jq "$1" "$SETTINGS" >"$tmp" && mv "$tmp" "$SETTINGS"
}

if [ "${1:-}" = "--uninstall" ]; then
  _ensure_settings
  _edit_settings 'del(.statusLine)'
  rm -f "$DEST"
  echo "✓ Removed statusLine from settings.json and deleted $DEST"
  echo "  (cache left at ~/.cache/claude-status — remove with: rm -rf ~/.cache/claude-status)"
  echo "  Restart Claude Code to apply."
  exit 0
fi

install -m 0755 "$SRC_DIR/statusbar.sh" "$DEST"
_ensure_settings
_edit_settings '.statusLine = {"type":"command","command":"~/.claude/statusbar.sh"}'

echo "✓ Installed statusbar.sh → $DEST"
echo "✓ Pointed statusLine in $SETTINGS at it"
echo "  Configure the cap with CLAUDE_MONTHLY_CAP (default 500)."
echo "  Restart Claude Code (or start a new session) to see it."
