#!/bin/bash
# Send a macOS notification when Codex finishes a turn

PAYLOAD="$1"
EVENT_TYPE=$(echo "$PAYLOAD" | jq -r '.type // empty' 2>/dev/null)

if [ "$EVENT_TYPE" != "agent-turn-complete" ]; then
  exit 0
fi

if [ -n "$TMUX_PANE" ]; then
  SESSION=$(tmux display-message -t "$TMUX_PANE" -p '#S' 2>/dev/null)
fi
SESSION=${SESSION:-$(basename "$PWD")}
SESSION=$(echo "$SESSION" | tr -d '()')

terminal-notifier -title "Codex" -subtitle "$SESSION" -message "Waiting for input" -sound Frog
