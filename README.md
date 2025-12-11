# dev
This is a repository for my development environment setup including dotfiles, neovim configuration, and system-specific configs. The goal is to be up and running on any machine quickly.

## What's included
- **env/**: Dotfiles (zsh, tmux, neovim, hyprland, kitty, waybar, rofi, fontconfig)
- **arch/**: Arch Linux specific configs and wallpapers
- **devcontainer/**: Development container configurations

## Setup

### Quick start (macOS with Homebrew)
1. `make install` - Install required dependencies (brew packages, rust toolchain)
2. `make` - Symlink dotfiles, build neovim from source, setup packer plugins
3. `make ensure-oh-my-zsh` - Install oh-my-zsh (optional)

### Manual steps
- **Symlink dotfiles only**: `make link`
- **Update neovim config**: `make update-nvim`

## Notes
- Neovim config is in a separate repo, referenced as a submodule at `env/.config/nvim`
- All dotfiles on the target machine are symlinks to files in this repo - changes here update your system immediately
- The default `make` target builds neovim v0.11.4 from source and configures it with packer plugins
