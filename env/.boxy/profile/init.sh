#!/usr/bin/env bash
set -euo pipefail

# Boxy runs this as root, but interactive sessions (ssh/attach/claude/codex) run
# as the `notion` user. Hand off to `notion` so the clone and `make boxy` land in
# /home/notion instead of /root.
runuser -u notion -- bash -lc '
  set -euo pipefail
  if [ ! -d ~/colm-dev ]; then
    git clone https://github.com/colm-notion/dev.git ~/colm-dev
  else
    git -C ~/colm-dev pull
  fi
  cd ~/colm-dev
  make boxy
'
