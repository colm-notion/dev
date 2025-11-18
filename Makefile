MKFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
DOTFILES := "$(dir $(MKFILE_PATH))env"
TARGET_DIR = $$HOME

DOTFILES_LIST = \
	.zshrc \
	.zsh_profile \
	.tmux.conf \
	.config/tmux \
	.config/nvim \
	.config/hypr \
	.config/kitty \
	.config/waybar \
	.config/fontconfig \
	.config/rofi \
	.fonts

all: link nvim update-nvim

link: $(DOTFILES_LIST)

$(DOTFILES_LIST):
	mkdir -p $(dir $(TARGET_DIR)/$@)
	ln -sfv $(DOTFILES)/$@ $(dir $(TARGET_DIR)/$@)

update-nvim:
	@git submodule update --init --recursive
	@cd $(DOTFILES)/.config/nvim && git pull origin main
	@git add $(DOTFILES)/.config/nvim
	@git commit -m "chore: bump nvim config to latest" || echo "No changes to commit"

.PHONY: ensure-oh-my-zsh
ensure-oh-my-zsh:
	@if [ ! -d ~/.oh-my-zsh ]; then \
		echo "Oh My Zsh not found. Installing..."; \
		RUNZSH=no CHSH=yes sh -c "$$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"; \
		chsh -s $$(which zsh); \
	fi;

PACKER=~/.local/share/nvim/site/pack/packer/start/packer.nvim
$(PACKER):
	@git clone --depth 1 https://github.com/wbthomason/packer.nvim $(PACKER)

NEOVIM_SOURCE=~/neovim
$(NEOVIM_SOURCE):
	@git clone https://github.com/neovim/neovim.git $(NEOVIM_SOURCE)

nvim: $(PACKER) build-neovim-src

BREW_PACKAGES := ninja cmake gettext curl git

.PHONY: install
install: $(BREW_PACKAGES) $(YAY_PACKAGES)

$(BREW_PACKAGES) &:
	@echo "Ensuring $@ is installed..."
	@brew list $@ > /dev/null 2>&1 || { \
		echo "Installing $@..."; \
		brew install $@; \
	}

build-neovim-src: $(NEOVIM_SOURCE) $(BREW_PACKAGES)
	@cd ~/neovim && \
	git checkout v0.11.4 && \
	make CMAKE_BUILD_TYPE=RelWithDebInfo && \
	sudo make install;

