#!/usr/bin/env bash
MODULE_NAME="Base System Configuration"
MODULE_DESC="/opt ownership change, apt update, xfce4-terminal, pipx install, go install, zsh datetime prompt, tmux with logging setup"
MODULE_CATEGORY="setup"

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

    # ── XFCE4 Terminal ───────────────────────────────────────────────────────────
    info "Installing XFCE4-Terminal..."
    apt_install xfce4-terminal

    local uid
    uid=$(id -u "$TARGET_USER")

    sudo -u "$TARGET_USER" env \
        DISPLAY=:0 \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        bash -c '
        xfconf-query -c xfce4-terminal -p /background-mode -s TERMINAL_BACKGROUND_SOLID --create -t string
        xfconf-query -c xfce4-terminal -p /color-background -s "#000000000000" --create -t string
        xfconf-query -c xfce4-terminal -p /color-foreground -s "#FFFAF4" --create -t string
        xfconf-query -c xfce4-terminal -p /color-cursor -s "#FFFAF4" --create -t string
        xfconf-query -c xfce4-terminal -p /color-bold-is-bright -s true --create -t bool
        xfconf-query -c xfce4-terminal -p /font-name -s "Fira Code weight=450 10" --create -t string
        xfconf-query -c xfce4-terminal -p /font-use-system -s false --create -t bool
        xfconf-query -c xfce4-terminal -p /misc-cursor-blinks -s true --create -t bool
        xfconf-query -c xfce4-terminal -p /misc-cursor-shape -s TERMINAL_CURSOR_SHAPE_IBEAM --create -t string
        xfconf-query -c xfce4-terminal -p /misc-menubar-default -s false --create -t bool
        xfconf-query -c xfce4-terminal -p /scrolling-unlimited -s true --create -t bool
        xfconf-query -c xfce4-terminal -p /title-mode -s TERMINAL_TITLE_HIDE --create -t string
    ' 2>> "$MODULE_LOG" && success "xfce4-terminal configured" || warn "xfce4-terminal config failed (may need display)"

    local helpers="/etc/xdg/xfce4/helpers.rc"
    mkdir -p "$(dirname "$helpers")"
    if grep -q "^TerminalEmulator=" "$helpers" 2>/dev/null; then
        sed -i 's|^TerminalEmulator=.*|TerminalEmulator=xfce4-terminal|' "$helpers"
    else
        echo "TerminalEmulator=xfce4-terminal" >> "$helpers"
    fi
    success "Default terminal set to xfce4-terminal"

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

    # ── tmux with logging capabilities ──────────────────────────────────────────────────────
    apt_install tmux git
 
    local tpm_dir="$USER_HOME/.tmux/plugins/tpm"
    local scripts_dir="$USER_HOME/.tmux/scripts"
    local logs_dir="$USER_HOME/tmux-logs"
    local tmux_conf="$USER_HOME/.tmux.conf"
    local logger_file="$scripts_dir/zsh-logger.zsh"
    local zshrc="$USER_HOME/.zshrc"
 
    mkdir -p "$scripts_dir" "$logs_dir"
 
    # ── Install TPM ──────────────────────────────────────────────────────────────
    if [[ ! -d "$tpm_dir/.git" ]]; then
        sudo -u "$TARGET_USER" git clone \
            https://github.com/tmux-plugins/tpm "$tpm_dir" >> "$MODULE_LOG" 2>&1 \
            && success "TPM installed" \
            || warn "TPM clone failed"
    else
        info "TPM already installed"
    fi
 
    # ── Write zsh-logger.zsh ─────────────────────────────────────────────────────
    cat > "$logger_file" << 'ZSH_LOGGER'
#!/usr/bin/env zsh
# zsh-logger.zsh — shell-side structured logger
# Captures: exact command text (preexec hook), full output (tee via fd),
# accurate timestamp (moment Enter is pressed), exit code, time taken.
# No pipe-pane. No terminal stream scraping. Zero control char issues.
#
# Log format:
#   [2025-04-13 14:32:01] nmap -sV 10.10.10.1
#   <command output here>
#   time: 12.341s | exit: 0
#   --------------------------------------------------
 
ZSH_LOG_DIR="${ZSH_LOG_DIR:-$HOME/tmux-logs}"
mkdir -p "$ZSH_LOG_DIR"
 
_zlog_resolve_file() {
    if [[ -n "${TMUX_PANE:-}" ]]; then
        local pane_id="${TMUX_PANE//%/}"
        local session window
        session=$(tmux display-message -p '#S' 2>/dev/null || echo "shell")
        window=$(tmux display-message  -p '#I' 2>/dev/null || echo "0")
        _ZLOG_FILE="$ZSH_LOG_DIR/tmux-${session}-w${window}-p${pane_id}.log"
    else
        _ZLOG_FILE="$ZSH_LOG_DIR/shell-$$.log"
    fi
    export _ZLOG_FILE
}
_zlog_resolve_file
 
if [[ ! -s "$_ZLOG_FILE" ]]; then
    {
        printf '=%.0s' {1..60}; printf '\n'
        printf ' Started : %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf ' Shell   : zsh (PID %d)\n' "$$"
        printf ' Pane    : %s\n' "${TMUX_PANE:-none}"
        printf ' Log     : %s\n' "$_ZLOG_FILE"
        printf '=%.0s' {1..60}; printf '\n\n'
    } >> "$_ZLOG_FILE"
fi
 
_ZLOG_CMD=""
_ZLOG_START_MS=0
_ZLOG_TMPOUT=""
_ZLOG_ACTIVE=0
 
_zlog_preexec() {
    local cmd="$1"
    [[ -z "$cmd" ]] && return 0
    [[ "$cmd" == _zlog* || "$cmd" == zlog_* ]] && return 0
 
    _ZLOG_CMD="$cmd"
    _ZLOG_START_MS=$(date +%s%3N)
    _ZLOG_ACTIVE=1
    _ZLOG_TMPOUT=$(mktemp "${TMPDIR:-/tmp}/.zlog_XXXXXX")
 
    printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$_ZLOG_CMD" \
        >> "$_ZLOG_FILE"
 
    exec 41>&1 42>&2
    exec 1> >(tee -a "$_ZLOG_TMPOUT" >&41) \
         2> >(tee -a "$_ZLOG_TMPOUT" >&42)
}
 
_zlog_precmd() {
    local exit_code=$?
    [[ "$_ZLOG_ACTIVE" -ne 1 ]] && return 0
    _ZLOG_ACTIVE=0
 
    exec 1>&41 2>&42
    exec 41>&- 42>&-
 
    local now_ms elapsed_ms elapsed_s
    now_ms=$(date +%s%3N)
    elapsed_ms=$(( now_ms - _ZLOG_START_MS ))
    elapsed_s=$(awk "BEGIN{printf \"%.3f\", $elapsed_ms/1000}")
 
    sleep 0.05
 
    [[ -s "$_ZLOG_TMPOUT" ]] && cat "$_ZLOG_TMPOUT" >> "$_ZLOG_FILE"
    rm -f "$_ZLOG_TMPOUT"
    _ZLOG_TMPOUT=""
 
    printf 'time: %ss | exit: %d\n' "$elapsed_s" "$exit_code" >> "$_ZLOG_FILE"
    printf -- '-%.0s' {1..50}; printf '\n'                     >> "$_ZLOG_FILE"
 
    _ZLOG_CMD=""
}
 
autoload -Uz add-zsh-hook
add-zsh-hook preexec _zlog_preexec
add-zsh-hook precmd  _zlog_precmd
 
zlog_stop() {
    add-zsh-hook -d preexec _zlog_preexec
    add-zsh-hook -d precmd  _zlog_precmd
    { exec 1>&41 2>&42; exec 41>&- 42>&-; } 2>/dev/null || true
    [[ -n "$_ZLOG_TMPOUT" ]] && rm -f "$_ZLOG_TMPOUT"
    print "[zsh-logger] stopped. log → $_ZLOG_FILE"
}
 
zlog_show() { tail -f "$_ZLOG_FILE"; }
 
print "[zsh-logger] active → $_ZLOG_FILE"
ZSH_LOGGER
 
    chmod +x "$logger_file"
    chown "$TARGET_USER:$TARGET_USER" "$logger_file"
    success "zsh-logger.zsh → $logger_file"
 
    # ── Auto-source from .zshrc when inside tmux ─────────────────────────────────
    local source_block
    source_block="# Auto-start shell logger in every tmux pane
[[ -n \"\${TMUX_PANE:-}\" && -f \"$logger_file\" ]] && source \"$logger_file\""
 
    [[ -f "$zshrc" ]] || touch "$zshrc"
    if ! grep -q "zsh-logger.zsh" "$zshrc"; then
        add_to_rc "$zshrc" "zsh-logger" "$source_block"
        chown "$TARGET_USER:$TARGET_USER" "$zshrc"
        success "Auto-source added to $zshrc"
    else
        info "zsh-logger already in $zshrc"
    fi
 
    # ── Write minimal tmux.conf (no pipe-pane, no auto-log hook needed) ──────────
    if [[ ! -f "$tmux_conf" ]]; then
        cat > "$tmux_conf" << 'TMUXCONF'
# Prefix
set -g prefix C-a
bind C-a send-prefix
unbind C-b
 
set -g mouse on
set -s escape-time 2
set -g history-limit 500000
set -g allow-rename off
set -g default-terminal "xterm-256color"
 
# Splits
bind - split-window -v
bind / split-window -h
 
# Vi copy mode
setw -g mode-keys vi
bind -T copy-mode-vi 'v' send-keys -X begin-selection
bind -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel 'xclip -in -selection clipboard'
 
# Pane join/send
bind-key j command-prompt -p "Join pane from:" "join-pane -s :'%%'"
bind-key s command-prompt -p "Send pane to:"   "join-pane -t :'%%'"
 
# Plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @resurrect-capture-pane-contents 'on'
 
run '~/.tmux/plugins/tpm/tpm'
TMUXCONF
        chown "$TARGET_USER:$TARGET_USER" "$tmux_conf"
        success "tmux.conf written → $tmux_conf"
    else
        info "tmux.conf already exists — not overwriting"
    fi
 
    chown -R "$TARGET_USER:$TARGET_USER" "$scripts_dir" "$logs_dir"
 
    success "Tmux logger installed"
    info "Logs → $logs_dir"
    info "Commands: zlog_show (tail log) | zlog_stop (stop logging)"
    info "Open tmux and press prefix + I to install plugins"
}