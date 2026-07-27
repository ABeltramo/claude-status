#!/usr/bin/env bash
# Installer for claude-status: puts statusbar.sh at ~/.claude/statusbar.sh and
# points the statusLine key in ~/.claude/settings.json at it. Idempotent.
#
#   ./install.sh              install / update (copies the script)
#   ./install.sh --link       symlink the script instead of copying, so editing
#                             the repo file is live immediately (one source of truth)
#   ./install.sh --uninstall  remove the statusLine key and the installed script/link
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

case "${1:-}" in
  --uninstall)
    _ensure_settings
    _edit_settings 'del(.statusLine)'
    rm -f "$DEST"   # removes a regular file or a symlink
    echo "✓ Removed statusLine from settings.json and deleted $DEST"
    echo "  (cache left at ~/.cache/claude-status — remove with: rm -rf ~/.cache/claude-status)"
    echo "  Restart Claude Code to apply."
    exit 0
    ;;
  --link)
    ln -sfn "$SRC_DIR/statusbar.sh" "$DEST"   # -n so re-linking doesn't nest into an existing dir symlink
    echo "✓ Symlinked $DEST → $SRC_DIR/statusbar.sh"
    ;;
  "")
    install -m 0755 "$SRC_DIR/statusbar.sh" "$DEST"
    echo "✓ Installed statusbar.sh → $DEST"
    ;;
  *)
    echo "usage: ./install.sh [--link | --uninstall]"; exit 1
    ;;
esac

_ensure_settings
_edit_settings '.statusLine = {"type":"command","command":"~/.claude/statusbar.sh"}'

echo "✓ Pointed statusLine in $SETTINGS at it"
echo "  Configure the cap with CLAUDE_MONTHLY_CAP (default 500)."
echo "  Restart Claude Code (or start a new session) to see it."
