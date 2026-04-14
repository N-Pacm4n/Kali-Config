#!/usr/bin/env bash
MODULE_NAME="Base System Configuration"
MODULE_DESC="/opt ownership change, apt update, pipx install, go install, zsh datetime prompt"
MODULE_CATEGORY="general"

install() {
    require_root

    # ── /opt ownership change ───────────────────────────────────────────────────────────────────
    info "Changing ownership of /opt..."
    if [[ -d /opt ]]; then
        chown -R "${TARGET_USER}:${TARGET_USER}" /opt
        info "Ownership of /opt changed to ${TARGET_USER}:${TARGET_USER}."
    else
        warn "/opt does not exist; skipping chown."
    fi

    # ── Update ───────────────────────────────────────────────────────────────────
    info "Running apt update..."
    apt update -y && apt dist-upgrade -y >> "$MODULE_LOG" 2>&1 && success "apt update done"

    # ── PIPX Install ──────────────────────────────────────────────────────
    info "Installing pipx..."
    apt_install pipx || pip3 install pipx --break-system-packages >> "$MODULE_LOG" 2>&1

    # Ensure pipx path is in shell rc
    local pipx_block
    pipx_block='export PATH="$PATH:$HOME/.local/bin"'

    for rc in "$USER_HOME/.bashrc" "$USER_HOME/.zshrc"; do
        [[ -f "$rc" ]] || touch "$rc"
        add_to_rc "$rc" "pipx-path" "$pipx_block"
        chown "$TARGET_USER:$TARGET_USER" "$rc"
    done

    sudo -u "$TARGET_USER" pipx ensurepath >> "$MODULE_LOG" 2>&1
    success "pipx ready"

    # ── Go install ──────────────────────────────────────────────────────
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)       go_arch="amd64" ;;
        aarch64|arm64) go_arch="arm64" ;;
        armv7l|armv6l) go_arch="armv6l" ;;
        *) fail "Unsupported architecture: $arch"; return 1 ;;
    esac

    info "Fetching latest Go version..."
    local latest_ver
    latest_ver="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1)"
    [[ -z "$latest_ver" ]] && { fail "Failed to fetch Go version"; return 1; }
    info "Latest: $latest_ver"

    local tarfile="${latest_ver}.linux-${go_arch}.tar.gz"
    local url="https://go.dev/dl/${tarfile}"
    local tmp
    tmp="$(mktemp -d)"

    info "Downloading $url"
    curl -fsSL -o "$tmp/$tarfile" "$url" >> "$MODULE_LOG" 2>&1 \
        || { fail "Download failed"; rm -rf "$tmp"; return 1; }

    [[ -d /usr/local/go ]] && { info "Removing old Go install"; rm -rf /usr/local/go; }

    info "Extracting to /usr/local..."
    tar -C /usr/local -xzf "$tmp/$tarfile" >> "$MODULE_LOG" 2>&1 \
        || { fail "Extraction failed"; rm -rf "$tmp"; return 1; }

    rm -rf "$tmp"
    chown -R "$TARGET_USER:$TARGET_USER" /usr/local/go
    success "Go installed: /usr/local/go"

    # Configure env in shell rc files
    local gopath="$USER_HOME/go"
    mkdir -p "$gopath"
    chown -R "$TARGET_USER:$TARGET_USER" "$gopath"

    local go_block
    go_block="export GOROOT=/usr/local/go
export GOPATH=$gopath
export PATH=\$PATH:\$GOROOT/bin:\$GOPATH/bin"

    for rc in "$USER_HOME/.bashrc" "$USER_HOME/.zshrc"; do
        [[ -f "$rc" ]] || touch "$rc"
        add_to_rc "$rc" "go-env" "$go_block"
        chown "$TARGET_USER:$TARGET_USER" "$rc"
        success "Go env added to $rc"
    done

    # ── ZSH Datetime prompt ──────────────────────────────────────────────────────
    if ! command -v zsh &>/dev/null; then
        apt_install zsh
    fi
 
    local zsh_path
    zsh_path="$(command -v zsh)"
    chsh -s "$zsh_path" "$TARGET_USER" 2>/dev/null \
        && success "Default shell → zsh" \
        || warn "chsh failed — run manually: chsh -s $zsh_path"
 
    local zshrc="$USER_HOME/.zshrc"
    if [[ -f "$zshrc" ]] && ! grep -q "%D{%Y-%m-%d %H:%M:%S}" "$zshrc"; then
        cp "$zshrc" "$zshrc.bak.$(date +%s)"
        sed -i \
            "s|PROMPT=\$'%F{%(#.blue.green)}┌──|PROMPT=\$'%F{%(#.blue.green)}┌── [%F{yellow}%D{%Y-%m-%d %H:%M:%S}%f] |" \
            "$zshrc" \
            && success "ZSH prompt updated with datetime" \
            || warn "Could not auto-patch ZSH prompt (Kali version may differ)"
    else
        info "ZSH datetime prompt already present or .zshrc not found"
    fi

}