MKFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
DOTFILES := "$(dir $(MKFILE_PATH))env"
TARGET_DIR = $$HOME

DOTFILES_LIST = \
	.boxy/profile/init.sh \
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

all: link nvim

boxy: link nvim-linux

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

nvim: $(PACKER) build-neovim-src neovim-packer-installs update-nvim git-ignore-config

BREW_PACKAGES := ninja cmake gettext curl git tmux ripgrep lua rustup btop eza withgraphite/tap/graphite gh terminal-notifier

.PHONY: install
install: install-rust install-brew

.PHONY: install-brew
install-brew: $(BREW_PACKAGES)

$(BREW_PACKAGES):
	@echo "Ensuring $@ is installed..."
	@brew list $@ > /dev/null 2>&1 || { \
		echo "Installing $@..."; \
		brew install $@; \
	}

install-rust: $(BREW_PACKAGES)
	@rustup-init
	@rustup toolchain install nightly

build-neovim-src: $(NEOVIM_SOURCE) $(BREW_PACKAGES)
	@cd ~/neovim && \
	git checkout v0.11.4 && \
	make CMAKE_BUILD_TYPE=RelWithDebInfo && \
	sudo make install;

APT_PACKAGES := ninja-build gettext cmake curl build-essential git tmux ripgrep lua5.4 gh

.PHONY: install-apt
install-apt:
	@missing=$$(for p in $(APT_PACKAGES); do dpkg -s $$p >/dev/null 2>&1 || echo $$p; done); \
	if [ -n "$$missing" ]; then \
		echo "Installing missing apt packages: $$missing"; \
		sudo apt-get update && sudo apt-get install -y $$missing; \
	else \
		echo "all apt packages already installed"; \
	fi

NVIM_VERSION := v0.11.4
build-neovim-src-linux: install-apt
	@if command -v nvim >/dev/null 2>&1 && nvim --version | head -1 | grep -q "$(NVIM_VERSION)"; then \
		echo "nvim $(NVIM_VERSION) already installed, skipping build"; \
	else \
		$(MAKE) $(NEOVIM_SOURCE) && \
		cd ~/neovim && \
		git checkout $(NVIM_VERSION) && \
		make CMAKE_BUILD_TYPE=RelWithDebInfo && \
		sudo make install; \
	fi

nvim-linux: $(PACKER) build-neovim-src-linux neovim-packer-installs update-nvim git-ignore-config

.PHONY: claude-hooks
claude-hooks:
	@mkdir -p $(TARGET_DIR)/.claude/scripts
	@cp $(DOTFILES)/.claude/scripts/notify-waiting.sh $(TARGET_DIR)/.claude/scripts/notify-waiting.sh
	@chmod +x $(TARGET_DIR)/.claude/scripts/notify-waiting.sh
	@if [ ! -f $(TARGET_DIR)/.claude/settings.json ]; then \
		echo '{}' > $(TARGET_DIR)/.claude/settings.json; \
	fi
	@jq '.hooks.Notification = [{"hooks": [{"type": "command", "command": "$(TARGET_DIR)/.claude/scripts/notify-waiting.sh"}]}]' \
		$(TARGET_DIR)/.claude/settings.json > $(TARGET_DIR)/.claude/settings.json.tmp \
		&& mv $(TARGET_DIR)/.claude/settings.json.tmp $(TARGET_DIR)/.claude/settings.json
	@echo "Claude hooks installed."

neovim-packer-installs:
	@nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerClean'
	@nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'
	@nvim --headless -c 'sleep 10' -c 'qall'
	@nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'
	@nvim --headless -c 'MasonUpdate' -c 'MasonInstall --force basedpyright terraform systemd-language-server typescript-language-server' -c 'quitall' || true

