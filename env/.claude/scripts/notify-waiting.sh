#!/bin/bash
# Send a macOS notification when Claude Code is waiting for input

if [ -n "$TMUX_PANE" ]; then
  SESSION=$(tmux display-message -t "$TMUX_PANE" -p '#S' 2>/dev/null)
fi
SESSION=${SESSION:-$(basename "$PWD")}
SESSION=$(echo "$SESSION" | tr -d '()')
terminal-notifier -title "Claude Code" -subtitle "$SESSION" -message "Waiting for input" -sound Frog
