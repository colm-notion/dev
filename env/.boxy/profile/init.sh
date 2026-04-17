#!/usr/bin/env bash
set -euo pipefail

git clone https://github.com/colm-notion/dev.git ~/dev
cd ~/dev
make
