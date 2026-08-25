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

# Boxy images moved to WizOS on 2026-08-20 (notion-next
# docker/remote-agent/Dockerfile). Three facts from that image define what this
# has to do:
#
#   1. apk on a RUNNING box always 401s. The WizOS repo credentials are
#      build-time-only secrets (WIZOS_CLIENT_ID/SECRET fed to `apk-auth` under
#      --mount=type=secret), so they don't exist at runtime. `apk add` is not a
#      tool this Makefile has, for anything.
#   2. wizos-base is "busybox + glibc only" — NOT musl, despite apk. So
#      neovim's official prebuilt Linux tarball runs here natively.
#   3. The image provisions tools with mise, not apk: tmux, gh and ripgrep all
#      come from docker/remote-agent/mise.toml, with the shim dir force-added to
#      PATH in /etc/profile.d/mise.sh (because `bash -lc`, which is how
#      .boxy/profile/init.sh runs, resets PATH and would drop it).
#
# So nvim is installed the same way the image installs everything else — via
# mise, from the prebuilt release. No cmake, no toolchain, no source build:
# cmake isn't in packages-apk.list and can't be added, which is what made the
# old apt-era source build unportable to these images.
NVIM_VERSION := v0.11.4
MISE_NVIM_VERSION := 0.11.4

# Fallback asset if mise is somehow absent. glibc, hence usable here.
NVIM_TARBALL_BASE := https://github.com/neovim/neovim/releases/download/$(NVIM_VERSION)

# `mise use -g` edits /home/notion/.config/mise/config.toml — the image's own
# mise config (it carries the tmux/gh/ripgrep pins). mise edits TOML in place so
# those survive, and a rebuilt box regenerates the file and re-runs this anyway.
.PHONY: nvim-boxy
nvim-boxy:
	@if command -v nvim >/dev/null 2>&1 && nvim --version | head -1 | grep -q "$(NVIM_VERSION)"; then \
		echo "nvim $(NVIM_VERSION) already installed"; \
		exit 0; \
	fi; \
	mise_bin="$$(command -v mise 2>/dev/null || true)"; \
	if [ -z "$$mise_bin" ] && [ -x "$$HOME/.local/bin/mise" ]; then \
		mise_bin="$$HOME/.local/bin/mise"; \
	fi; \
	if [ -n "$$mise_bin" ]; then \
		echo "nvim: installing $(MISE_NVIM_VERSION) via mise"; \
		"$$mise_bin" use -g neovim@$(MISE_NVIM_VERSION); \
	else \
		echo "nvim: mise not found, falling back to the prebuilt tarball"; \
		case "$$(uname -m)" in \
			x86_64) asset=nvim-linux-x86_64.tar.gz ;; \
			aarch64|arm64) asset=nvim-linux-arm64.tar.gz ;; \
			*) echo "nvim: no prebuilt asset for $$(uname -m)"; exit 1 ;; \
		esac; \
		mkdir -p "$$HOME/.local" && \
		curl -fsSL $(NVIM_TARBALL_BASE)/$$asset \
			| tar xz -C "$$HOME/.local" --strip-components=1; \
	fi

# NOTE: no `update-nvim` here (unlike the laptop `nvim` target). On a box the nvim
# config arrives via the dotfiles channel (~/.config/nvim), not the git submodule,
# and `update-nvim` would try to bump+commit the submodule — which aborts the build
# when the repo pins a submodule commit that no longer exists on the remote.
nvim-linux: $(PACKER) nvim-boxy neovim-packer-installs

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

# PATH: nvim arrives either as a mise shim or unpacked into ~/.local/bin, and
# neither is guaranteed on PATH in the same make run that installed it.
neovim-packer-installs: export PATH := $(HOME)/.local/share/mise/shims:$(HOME)/.local/bin:$(PATH)
neovim-packer-installs:
	@nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerClean'
	@nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'
	@nvim --headless -c 'sleep 10' -c 'qall'
	@nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'
	@nvim --headless -c 'MasonUpdate' -c 'MasonInstall --force basedpyright terraform systemd-language-server typescript-language-server' -c 'quitall' || true

