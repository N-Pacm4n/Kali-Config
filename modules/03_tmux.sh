MODULE_NAME="Tmux Setup"
MODULE_DESC="Setup tmux with logging and log export functionality"
MODULE_CATEGORY="general"   

install() {
    
    require_root
    
    # ── XFCE4 Terminal ───────────────────────────────────────────────────────────
    info "Installing XFCE4-Terminal..."
    apt_install xfce4-terminal tmux git zip

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
 
    local tpm_dir="$USER_HOME/.tmux/plugins/tpm"
    local scripts_dir="$USER_HOME/.tmux/scripts"
    local logs_dir="$USER_HOME/tmux-logs"
    local tmux_conf="$USER_HOME/.tmux.conf"
    local logger_file="$scripts_dir/zip-logs.sh"
    local zshrc="$USER_HOME/.zshrc"
 
    sudo -u "$TARGET_USER" mkdir -p "$tpm_dir" "$scripts_dir" "$logs_dir"
 
    # ── Install TPM ──────────────────────────────────────────────────────────────
    if [[ ! -d "$tpm_dir/.git" ]]; then
        sudo -u "$TARGET_USER" git clone \
            https://github.com/tmux-plugins/tpm "$tpm_dir" >> "$MODULE_LOG" 2>&1 \
            && success "TPM installed" \
            || warn "TPM clone failed"
    else
        info "TPM already installed"
    fi

# ── Write log-zip.zsh ─────────────────────────────────────────────────────
    cat > "$logger_file" << 'ZSH_LOGGER'
#!/usr/bin/env bash

LOG_DIR="${TMUX_LOG_DIR:-$HOME/tmux-logs}"
[[ -d "$LOG_DIR" ]] || exit 0

shopt -s nullglob
logs=("$LOG_DIR"/*.log)

if [[ ${#logs[@]} -eq 0 ]]; then
    tmux display-message "[*] No logs — nothing to archive"
    exit 0
fi

command -v zip >/dev/null || exit 0

created_epoch=$(tmux show-environment -g ZLOG_STARTED 2>/dev/null | cut -d= -f2)

# fallback if not set
[[ -z "$created_epoch" ]] && created_epoch=$(date +%s)

created_human=$(date -d "@$created_epoch" '+%Y-%m-%d_%H-%M-%S')

zip_file="$LOG_DIR/tmux-session-${created_human}-logs.zip"

(
  cd "$LOG_DIR" || exit 0
  zip -q "$zip_file" *.log
)
rm -f "${logs[@]}"
tmux display-message "[+] Logs archived → $(basename "$zip_file")"

ZSH_LOGGER
 
    chmod +x "$logger_file"
    chown "$TARGET_USER:$TARGET_USER" "$logger_file"
    success "zip-logs.sh → $logger_file"

# ── Auto-source from .zshrc when inside tmux ─────────────────────────────────
commandBlock=$(cat << 'EOF'
zmodload zsh/datetime

_ZLOG_CMD=""
_ZLOG_START=0.0

_zlog_get_logfile() {
    local LOG_DIR="${TMUX_LOG_DIR:-$HOME/tmux-logs}"
    mkdir -p "$LOG_DIR"

    local session window pane created_epoch created_human
    session=$(tmux display-message -p '#S')
    window=$(tmux display-message -p '#I')
    pane=$(tmux display-message -p '#{pane_id}' | tr -d '%')
    created_epoch=$(tmux display-message -p '#{session_created}')

    echo "$LOG_DIR/tmux-${created_epoch}-${session}-${window}-${pane}.log"
}

_zlog_format_duration() {
    awk -v e="$1" 'BEGIN {
        h  = int(e / 3600)
        m  = int(e % 3600 / 60)
        s  = int(e % 60)
        ms = int((e - int(e)) * 1000)
        if      (h > 0) printf "%dh %dm %ds",  h, m, s
        else if (m > 0) printf "%dm %ds %dms", m, s, ms
        else if (s > 0) printf "%ds %dms",     s, ms
        else            printf "%dms",         ms
    }'
}

_zlog_write_header() {
    local LOG_FILE="$1"
    {
        printf '=%.0s' {1..60}; printf '\n'
        printf ' Session : %s\n' "$(tmux display-message -p '#S')"
        printf ' Started : %s\n' "$(strftime '%Y-%m-%d %H:%M:%S' $EPOCHSECONDS)"
        printf '=%.0s' {1..60}; printf '\n\n'
    } >> "$LOG_FILE"
}

_zlog_preexec() {
    [[ -n "$TMUX" ]] || return
    tmux show-environment -g ZLOG 2>/dev/null | grep -q "ZLOG=1" || return
    [[ -z "$1" ]] && return

    _ZLOG_CMD="$1"
    _ZLOG_START=$EPOCHREALTIME

    local LOG_FILE
    LOG_FILE=$(_zlog_get_logfile)

    # Write header if file is new/empty
    [[ ! -s "$LOG_FILE" ]] && _zlog_write_header "$LOG_FILE"

    # Start pipe-pane capture only when a command runs — avoids
    # capturing autosuggestion ghost text during idle typing
    tmux pipe-pane -o "exec stdbuf -oL sed \
        -e 's/\x1b\][^\x07]*\x07//g' \
        -e 's/\x1b\][^\x1b]*\x1b\\\\//g' \
        -e 's/\x1b[P][^\x1b]*\x1b\\\\//g' \
        -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' \
        -e 's/\x1b[][()][AB012]//g' \
        -e 's/\x1b[=>]//g' \
        -e 's/\x1b.//g' \
        -e 's/\r//g' \
        -e 's/\r/\n/g' \
        -e 's/[[:space:]]\+$//' \
        -e '/^[[:space:]]*┌──/d' \
        -e '/^└─/d' \
        -e '/^[[:space:]]*quote>/d' \
        -e '/^[[:space:]]*dquote>/d' \
        -e '/^[[:space:]]*cmdsubst>/d' \
        | stdbuf -oL tr -d '\000\007\010\033' >> '$LOG_FILE'"

    printf '\n[%s] $ %s\n' \
        "$(strftime '%Y-%m-%d %H:%M:%S' $EPOCHSECONDS)" \
        "$_ZLOG_CMD" >> "$LOG_FILE"
}

_zlog_precmd() {
    local exit_code=$?
    [[ -n "$TMUX" ]] || return
    tmux show-environment -g ZLOG 2>/dev/null | grep -q "ZLOG=1" || return
    [[ -z "$_ZLOG_CMD" ]] && return

    # Stop capture between commands — no idle typing leaks
    tmux pipe-pane

    local LOG_FILE
    LOG_FILE=$(_zlog_get_logfile)
    local duration
    duration=$(_zlog_format_duration $(( EPOCHREALTIME - _ZLOG_START )))

    local status_str
    case $exit_code in
        0)   status_str="ok" ;;
        1)   status_str="err" ;;
        126) status_str="not executable" ;;
        127) status_str="command not found" ;;
        130) status_str="SIGINT (Ctrl+C)" ;;
        131) status_str="SIGQUIT" ;;
        137) status_str="SIGKILL" ;;
        143) status_str="SIGTERM" ;;
        *)   status_str="exit $exit_code" ;;
    esac

    sed -i '${/^$/d;}' "$LOG_FILE"

    printf '[Duration: %s | Exit: %d %s]\n' \
        "$duration" "$exit_code" "$status_str" >> "$LOG_FILE"

    _ZLOG_CMD=""
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _zlog_preexec
add-zsh-hook precmd  _zlog_precmd
EOF
)

tmuxAliases=$(cat << 'EOF'
# -------- Tmux Aliases --------
ktx() {
[[ -n "$TMUX" ]] || { echo "Not inside tmux"; return; }
local session
session=$(tmux display-message -p '#S')
tmux kill-session -t "$session"
}

tmx() {
    local session="$1"
    local mode="$2"

    # Ask for session name if not provided
    if [[ -z "$session" ]]; then
        read "session?Enter session name: "
    fi

    # Default fallback
    [[ -z "$session" ]] && session="main"

    # Check if session exists
    if tmux has-session -t "$session" 2>/dev/null; then
        tmux attach -t "$session"
        return
    fi
    
    # Enable logging if requested
    if [[ "$mode" == "--log" ]]; then
        TMUX_LOGGING=1 tmux new-session -s "$session"
    else
        tmux new-session -s "$session"
    fi
}
EOF
)

    [[ -f "$zshrc" ]] || touch "$zshrc"
    if ! grep -q "zsh-logger.zsh" "$zshrc"; then
        add_to_rc "$zshrc" "command logger" "$commandBlock"
        add_to_rc "$zshrc" "Tmux aliases" "$tmuxAliases"
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
set -g status-style 'bg=black,fg=white'
set -g status-right '#[fg=white,bg=black]#{?ZLOG,[Log ON],[Log OFF]} #[fg=white,bg=black]| CPU: #(grep "cpu " /proc/stat | awk "{u=\$2+\$4; t=\$2+\$3+\$4+\$5; print int(u/t*100)}"%%) #[fg=white,bg=black]| RAM: #(free -m | awk "/^Mem/{printf \"%.0f%%%%\", \$3/\$2*100}") #[fg=white,bg=black]| Load: #(cut -d" " -f1 /proc/loadavg)'

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

# ── Logging toggle (all panes in session) ────────────────────────────────────
bind-key L run-shell "
    if tmux show-environment -g ZLOG 2>/dev/null | grep -q ZLOG=1; then
        tmux set-environment -gu ZLOG
        tmux set-environment -gu ZLOG_STARTED
        tmux display-message 'Logging OFF'
    else
        tmux set-environment -g ZLOG 1
        tmux set-environment -g ZLOG_STARTED "$(date +%s)"
        tmux display-message 'Logging ON'
    fi"

bind-key Z run-shell "~/.tmux/scripts/zip-logs.sh"

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
    info "Open tmux and press prefix + I to install plugins"    
}