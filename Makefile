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
boxy: ensure-oh-my-zsh-boxy install-apk-extras nvim-linux mkdp-server

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
# manager is apk, not apt-get.
#
# Build deps are neovim's own Alpine list from BUILD.md, verbatim:
#   apk add build-base cmake coreutils curl gettext-tiny-dev git
# Note gettext-TINY-dev (Alpine's split) and coreutils (busybox's are too thin).
# Ninja is deliberately absent: BUILD.md calls it optional — cmake falls back to
# the Unix Makefiles generator — and it isn't in the WizOS index anyway. Since
# there's no ninja to parallelise the build for us, the nvim build below passes
# -j explicitly, which BUILD.md tells you NOT to do when ninja is present.
APK_BUILD_DEPS := build-base cmake coreutils curl git

# gettext: BUILD.md's Alpine line names gettext-tiny-dev, but the WizOS index
# serves neither variant and these boxes already ship the full gettext-dev — so
# asking for the tiny one turns a satisfied dep into a hard failure. Accept
# whichever is present; only try to install if neither is.
APK_GETTEXT_ALT := gettext-dev gettext-tiny-dev

# Not needed to build nvim, just wanted on a box. Installed one-at-a-time and
# best-effort: the WizOS index can't serve all of these, and a box without gh is
# still a box worth having, whereas a hard failure here aborts `make boxy`
# before nvim is ever built.
# pkg:binary — the binary is checked first, because `apk info -e` only knows
# about apk-installed packages and these images ship some tools outside apk
# (node is in /usr/local/bin that way). Without this, apk is asked for packages
# whose binaries are already on PATH.
APK_EXTRAS := tmux:tmux ripgrep:rg lua5.4:lua5.4 github-cli:gh

# `apk update` exits with the NUMBER of unreachable repositories, so it must not
# gate an install: the os.wiz.io repos are authenticated and 401 for this box,
# which made a plain `apk update && apk add` abort with "Error 3" before apk add
# ever ran. Refresh best-effort and let apk add speak for itself.

# `make boxy` runs as the unprivileged `notion` user, and hardened WizOS images
# don't necessarily ship sudo — fall back to doas, or to nothing when already
# root.
SUDO := $(shell if [ "`id -u`" = 0 ]; then echo; elif command -v sudo >/dev/null 2>&1; then echo sudo; elif command -v doas >/dev/null 2>&1; then echo doas; fi)

# Best-effort: on a box whose apk repos 401, none of this may be installable.
# The real gates are the cc and cmake checks in build-neovim-src-linux, which
# don't care how a tool arrived. Only invoked when a build is actually needed —
# an already-provisioned nvim shouldn't require cmake at all.
.PHONY: install-apk-build-deps
install-apk-build-deps:
	@missing=$$(for p in $(APK_BUILD_DEPS); do [ -n "$$(apk info -e $$p 2>/dev/null)" ] || echo $$p; done); \
	have_gettext=; \
	for p in $(APK_GETTEXT_ALT); do \
		[ -n "$$(apk info -e $$p 2>/dev/null)" ] && have_gettext=$$p; \
	done; \
	if [ -n "$$have_gettext" ]; then echo "gettext: $$have_gettext present"; else missing="$$missing gettext-dev"; fi; \
	missing=$$(echo $$missing); \
	if [ -z "$$missing" ]; then echo "nvim build deps: all present"; exit 0; fi; \
	echo "Installing nvim build deps: $$missing"; \
	$(SUDO) apk update || echo "apk update: some repos unreachable, using cached index"; \
	$(SUDO) apk add $$missing || echo "apk could not satisfy: $$missing (continuing — ensure-cmake covers cmake)"

.PHONY: install-apk-extras
install-apk-extras:
	@missing=; \
	for e in $(APK_EXTRAS); do \
		pkg=$${e%%:*}; bin=$${e##*:}; \
		command -v $$bin >/dev/null 2>&1 && continue; \
		[ -n "$$(apk info -e $$pkg 2>/dev/null)" ] && continue; \
		missing="$$missing $$pkg"; \
	done; \
	missing=$$(echo $$missing); \
	if [ -z "$$missing" ]; then echo "extras: all present"; exit 0; fi; \
	echo "Installing extras (best-effort): $$missing"; \
	$(SUDO) apk update >/dev/null 2>&1 || true; \
	for p in $$missing; do \
		$(SUDO) apk add $$p || echo "extras: $$p unavailable, skipping"; \
	done

# cmake is the one non-negotiable build dep, and it's absent from the WizOS
# cached index while os.wiz.io 401s. cmake can build itself with nothing but a
# C++ toolchain (which these images do ship), so bootstrap it rather than let
# `make boxy` dead-end on a repo-auth problem outside this repo's control.
#
# Pinned to the 3.x series on purpose: cmake 4 dropped compatibility with the
# pre-3.5 minimums that neovim's bundled deps (luajit, libuv, et al) still
# declare, so a 4.x bootstrap builds fine and then fails to configure neovim.
# Installed under ~/.local so it needs no root and won't shadow or collide with
# an apk-provided cmake if the repos ever come back.
CMAKE_VERSION := 3.31.7
LOCAL_PREFIX := $$HOME/.local
CMAKE_SRC := $$HOME/src/cmake-$(CMAKE_VERSION)

.PHONY: ensure-cmake
ensure-cmake:
	@if command -v cmake >/dev/null 2>&1; then \
		echo "cmake: $$(cmake --version | head -1) already available"; \
	elif [ -x $(LOCAL_PREFIX)/bin/cmake ]; then \
		echo "cmake: $(LOCAL_PREFIX)/bin/cmake present (not on PATH — the nvim build adds it)"; \
	else \
		echo "cmake: not installable via apk, bootstrapping $(CMAKE_VERSION) from source (this takes a while)..."; \
		command -v c++ >/dev/null 2>&1 || command -v g++ >/dev/null 2>&1 || { \
			echo "cmake: no C++ compiler — install build-base first (apk add build-base)"; \
			exit 1; \
		}; \
		mkdir -p $$HOME/src && \
		if [ ! -d $(CMAKE_SRC) ]; then \
			curl -fsSL https://github.com/Kitware/CMake/releases/download/v$(CMAKE_VERSION)/cmake-$(CMAKE_VERSION).tar.gz \
				| tar xz -C $$HOME/src; \
		fi && \
		cd $(CMAKE_SRC) && \
		./bootstrap --prefix=$(LOCAL_PREFIX) --parallel=$$(nproc) -- -DCMAKE_USE_OPENSSL=OFF && \
		make -j$$(nproc) && \
		make install && \
		echo "cmake: bootstrapped to $(LOCAL_PREFIX)/bin/cmake"; \
	fi

NVIM_VERSION := v0.11.4
build-neovim-src-linux:
	@if command -v nvim >/dev/null 2>&1 && nvim --version | head -1 | grep -q "$(NVIM_VERSION)"; then \
		echo "nvim $(NVIM_VERSION) already installed, skipping build"; \
	else \
		$(MAKE) install-apk-build-deps && \
		$(MAKE) ensure-cmake && \
		{ command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || { \
			echo "no C compiler on PATH — cannot build nvim"; exit 1; }; } && \
		$(MAKE) $(NEOVIM_SOURCE) && \
		cd ~/neovim && \
		git checkout $(NVIM_VERSION) && \
		PATH="$(LOCAL_PREFIX)/bin:$$PATH" make -j$$(nproc) CMAKE_BUILD_TYPE=RelWithDebInfo && \
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

