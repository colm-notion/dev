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

# Runs ON the box, AS the notion user (see .boxy/profile/init.sh). Installs only —
# configs come from the dotfiles channel (make boxy-dotfiles, run on the laptop).
boxy: ensure-oh-my-zsh-boxy nvim-linux mkdp-server

# Boxy-safe oh-my-zsh install: just clone the repo (no curl|sh, no chsh prompt).
.PHONY: ensure-oh-my-zsh-boxy
ensure-oh-my-zsh-boxy:
	@[ -d ~/.oh-my-zsh ] || git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh

link: $(DOTFILES_LIST)

$(DOTFILES_LIST):
	mkdir -p $(dir $(TARGET_DIR)/$@)
	ln -sfv $(DOTFILES)/$@ $(dir $(TARGET_DIR)/$@)

# Symlinks nvim/tmux/zsh dotfiles into ~/.boxy/profile/dotfiles so Boxy syncs
# them into the session user's home (the documented dotfiles channel). init.sh
# runs as root and lands in /root, so it's the wrong place for user dotfiles.
BOXY_DOTFILES_DIR = $$HOME/.boxy/profile/dotfiles
BOXY_DOTFILES_LIST = \
	.zshrc \
	.zsh_profile \
	.tmux.conf \
	.claude \
	.codex \
	.config/tmux \
	.config/nvim

.PHONY: boxy-dotfiles
boxy-dotfiles:
	@for f in $(BOXY_DOTFILES_LIST); do \
		dest="$(BOXY_DOTFILES_DIR)/$$f"; \
		mkdir -p "$$(dirname "$$dest")"; \
		ln -sfvn $(DOTFILES)/$$f "$$dest"; \
	done

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

nvim: $(PACKER) build-neovim-src update-nvim neovim-packer-installs

BREW_PACKAGES := ninja cmake gettext curl git tmux ripgrep lua rustup btop eza withgraphite/tap/graphite gh terminal-notifier watch fzf

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

# Boxy images are WizOS (Alpine-based) as of 2026-08-20, so the box package
# manager is apk, not apt-get. Debian names translated: build-essential ->
# build-base, gettext -> gettext-dev, and ninja-build only ships /usr/bin/
# ninja-build — neovim's Makefile looks for plain `ninja`, which comes from the
# ninja-is-really-ninja shim. github-cli IS in Alpine's community repo, so gh
# no longer needs the third-party-repo dance the Debian images required.
# ripgrep, ninja-build and github-cli live in community: that repo must be
# enabled in /etc/apk/repositories or `apk add` will fail to find them.
APK_PACKAGES := ninja-build ninja-is-really-ninja gettext-dev cmake curl build-base \
	git tmux ripgrep lua5.4 unzip github-cli

# `make boxy` runs as the unprivileged `notion` user, and hardened WizOS images
# don't necessarily ship sudo — fall back to doas, or to nothing when already
# root.
SUDO := $(shell if [ "`id -u`" = 0 ]; then echo; elif command -v sudo >/dev/null 2>&1; then echo sudo; elif command -v doas >/dev/null 2>&1; then echo doas; fi)

.PHONY: install-apk
install-apk:
	@missing=$$(for p in $(APK_PACKAGES); do [ -n "$$(apk info -e $$p 2>/dev/null)" ] || echo $$p; done); \
	if [ -n "$$missing" ]; then \
		echo "Installing missing apk packages: $$missing"; \
		$(SUDO) apk update && $(SUDO) apk add $$missing; \
	else \
		echo "all apk packages already installed"; \
	fi

NVIM_VERSION := v0.11.4
build-neovim-src-linux: install-apk
	@if command -v nvim >/dev/null 2>&1 && nvim --version | head -1 | grep -q "$(NVIM_VERSION)"; then \
		echo "nvim $(NVIM_VERSION) already installed, skipping build"; \
	else \
		$(MAKE) $(NEOVIM_SOURCE) && \
		cd ~/neovim && \
		git checkout $(NVIM_VERSION) && \
		make CMAKE_BUILD_TYPE=RelWithDebInfo && \
		$(SUDO) make install; \
	fi

# NOTE: no `update-nvim` here (unlike the laptop `nvim` target). On a box the nvim
# config arrives via the dotfiles channel (~/.config/nvim), not the git submodule,
# and `update-nvim` would try to bump+commit the submodule — which aborts the build
# when the repo pins a submodule commit that no longer exists on the remote.
nvim-linux: $(PACKER) build-neovim-src-linux neovim-packer-installs

# markdown-preview.nvim needs a server: either its prebuilt binary (app/bin) or
# node deps (app/node_modules with tslib). The plugin's packer `run` hook calls
# mkdp#util#install() asynchronously, but `neovim-packer-installs` quits headless
# nvim on a fixed sleep before the download finishes — so the box ends up with an
# empty app/bin AND no node_modules, and :MarkdownPreview crashes with
# "Cannot find module 'tslib'". Run mkdp's own install.sh synchronously here to
# fetch the prebuilt binary; fall back to node deps on arches with no binary.
MKDP_APP = $$HOME/.local/share/nvim/site/pack/packer/start/markdown-preview.nvim/app
.PHONY: mkdp-server
mkdp-server:
	@if [ ! -d $(MKDP_APP) ]; then \
		echo "mkdp: plugin not installed, skipping"; \
	else \
		echo "mkdp: installing preview server..."; \
		( cd $(MKDP_APP) && bash install.sh ) || true; \
		if ls $(MKDP_APP)/bin/markdown-preview-* >/dev/null 2>&1; then \
			echo "mkdp: prebuilt binary ready."; \
		else \
			echo "mkdp: no prebuilt binary for this arch; installing node deps..."; \
			( cd $(MKDP_APP) && npm install --no-audit --no-fund ); \
		fi; \
	fi

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

.PHONY: codex-hooks
codex-hooks:
	@mkdir -p $(TARGET_DIR)/.codex/scripts
	@cp $(DOTFILES)/.codex/scripts/notify-turn-complete.sh $(TARGET_DIR)/.codex/scripts/notify-turn-complete.sh
	@chmod +x $(TARGET_DIR)/.codex/scripts/notify-turn-complete.sh
	@SCRIPT="$$HOME/.codex/scripts/notify-turn-complete.sh"; \
	if [ ! -f $(TARGET_DIR)/.codex/config.toml ]; then \
		printf 'notify = ["%s"]\n\n[tui]\nnotifications = true\nnotification_condition = "unfocused"\n' "$$SCRIPT" \
			> $(TARGET_DIR)/.codex/config.toml; \
	elif ! grep -q '^notify' $(TARGET_DIR)/.codex/config.toml; then \
		printf '\nnotify = ["%s"]\n' "$$SCRIPT" \
			>> $(TARGET_DIR)/.codex/config.toml; \
	fi
	@echo "Codex hooks installed."

neovim-packer-installs:
	@nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerClean'
	@nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'
	@nvim --headless -c 'sleep 10' -c 'qall'
	@nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'
	@nvim --headless -c 'MasonUpdate' -c 'MasonInstall --force basedpyright terraform systemd-language-server typescript-language-server' -c 'quitall' || true

