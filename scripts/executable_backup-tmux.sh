#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="$HOME/.tmux-backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT="$BACKUP_DIR/tmux_sessions_${TIMESTAMP}.txt"

mkdir -p "$BACKUP_DIR"

tmux list-sessions -F "#{session_name} | windows: #{session_windows} | created: #{t:session_created}" > "$OUTPUT" 2>&1 \
  && echo "Saved to $OUTPUT" \
  || echo "No tmux sessions running"

# Keep only the 20 most recent backups
ls -t "$BACKUP_DIR"/tmux_sessions_*.txt | tail -n +21 | xargs rm -f
