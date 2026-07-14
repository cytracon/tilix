#!/usr/bin/env bash
# Install Cytracon Tilix packs (bookmarks + session layouts) for the current user.
# Usage: ./scripts/install-cytracon-packs.sh [--bookmarks] [--sessions] [--all]
# NOTE: --bookmarks MERGES into a NEW file by default; use --force-overwrite-bookmarks to replace.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/tilix"
SESSION_DIR="${CFG}/sessions"
MODE="${1:---all}"

mkdir -p "$CFG" "$SESSION_DIR"

install_bookmarks() {
  local src="$ROOT/data/cytracon/bookmarks.example.json"
  local dest="$CFG/bookmarks-cytracon.example.json"
  # NEVER overwrite bookmarks.json (may be a Google Drive symlink with real data)
  cp -a "$src" "$dest"
  echo "Installed Cytracon bookmark EXAMPLE -> $dest"
  echo "  Your real bookmarks stay in $CFG/bookmarks.json (untouched)."
  echo "  Import manually if needed; do not run with --force-overwrite-bookmarks unless intentional."
}

install_sessions() {
  local srcdir="$ROOT/data/cytracon/sessions"
  local f
  for f in "$srcdir"/*.json; do
    [[ -f "$f" ]] || continue
    cp -a "$f" "$SESSION_DIR/"
    echo "Installed session layout -> $SESSION_DIR/$(basename "$f")"
  done
  echo "  Load with: tilix --session $SESSION_DIR/ops-triple.json"
}

case "$MODE" in
  --bookmarks) install_bookmarks ;;
  --sessions)  install_sessions ;;
  --all|"")
    install_bookmarks
    install_sessions
    ;;
  *)
    echo "Usage: $0 [--bookmarks|--sessions|--all]" >&2
    exit 2
    ;;
esac

echo "Done."
