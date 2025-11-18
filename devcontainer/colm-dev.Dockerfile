FROM mcr.microsoft.com/devcontainers/python:1-3.11-bookworm

RUN echo "Configuring Colm's dev environment..."

USER 1000:1000

RUN sudo apt-get update && \
    sudo apt-get install -y \
    ninja-build gettext cmake unzip curl build-essential tmux ripgrep exa

# --- Install Rust early (stable toolchain, won't change often) ---
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
ENV PATH="/home/vscode/.cargo/bin:${PATH}"

# build neovim
RUN git clone https://github.com/neovim/neovim.git /home/vscode/neovim && \
    cd /home/vscode/neovim && \
    git checkout v0.11.4 && \
    make CMAKE_BUILD_TYPE=RelWithDebInfo && \
    sudo make install

USER root

# Install dependencies and Go
ENV GO_VERSION=1.24.2

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates tar \
    && curl -fsSL https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz -o /tmp/go.tar.gz \
    && rm -rf /usr/local/go \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Add Go to PATH
ENV PATH="/usr/local/go/bin:${PATH}"

USER vscode

# -> NOTE ^ these are the expensive ones. Try not to bust the cache above here

RUN curl -o /home/vscode/.git-completion.bash https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash

# Append git-completion source command to .bashrc
RUN echo 'if [ -f ~/.git-completion.bash ]; then\n  . ~/.git-completion.bash\nfi' >> /home/vscode/.bashrc

# Link my dotfiles
COPY ./env/ /home/vscode/dev/env/
COPY ./Makefile /home/vscode/dev/Makefile
RUN make -C /home/vscode/dev

RUN sudo chown -R 1000:1000 /home/vscode/dev
RUN sudo chmod -R 755 /home/vscode/dev
RUN sudo chown -R 1000:1000 /home/vscode/.config
RUN sudo chmod -R 755 /home/vscode/.config
RUN find /home/vscode/dev/env -type f -name 'packer_compiled.lua' -delete

# install plugins and quit when done
RUN make -C /home/vscode/dev neovim-packer-installs
