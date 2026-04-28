#!/usr/bin/env bash
set -euo pipefail

if [ ! -d ~/colm-dev ]; then
  git clone https://github.com/colm-notion/dev.git ~/colm-dev
else
  git -C ~/colm-dev pull
fi
cd ~/colm-dev
make boxy
