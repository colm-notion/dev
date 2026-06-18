#!/usr/bin/env bash
set -euo pipefail

# 1. Install Neovim (macOS)
brew install neovim

# 2. Install packer, the plugin manager
git clone --depth 1 https://github.com/wbthomason/packer.nvim \
  "$HOME/.local/share/nvim/site/pack/packer/start/packer.nvim"

# 3. Write a minimal config with vim-be-good, then install it
mkdir -p "$HOME/.config/nvim"
cat > "$HOME/.config/nvim/init.lua" <<'EOF'
require('packer').startup(function(use)
  use 'wbthomason/packer.nvim'
  use 'ThePrimeagen/vim-be-good'
end)
EOF
nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'
