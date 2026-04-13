MODULE_NAME="Tmux Setup"
MODULE_DESC="Setup tmux with logging and log export functionality"
MODULE_CATEGORY="general"   

install() {
        apt_install tmux git zip
 
    local tpm_dir="$USER_HOME/.tmux/plugins/tpm"
    local scripts_dir="$USER_HOME/.tmux/scripts"
    local logs_dir="$USER_HOME/tmux-logs"
    local tmux_conf="$USER_HOME/.tmux.conf"
    local logger_file="$scripts_dir/zsh-logger.zsh"
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
 
    # ── Write zsh-logger.zsh ─────────────────────────────────────────────────────
    cat > "$logger_file" << 'ZSH_LOGGER'
#!/usr/bin/env bash

LOG_DIR="${TMUX_LOG_DIR:-$HOME/tmux-logs}"
mkdir -p "$LOG_DIR"

SESSION=$(tmux display-message -p '#S')
WINDOW=$(tmux display-message -p '#I')
PANE=$(tmux display-message -p '#{pane_id}' | tr -d '%')
TIMESTAMP=$(date "+%Y-%m-%d_%H-%M-%S")

LOG_FILE="$LOG_DIR/tmux-${SESSION}-${WINDOW}-${PANE}.log"

FILTER='
  use strict;
  $| = 1;
  while (<STDIN>) {
    s/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)//g;
    s/\x1b[P][^\x1b]*\x1b\\//g;
    s/\x1b\[[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]//g;
    s/\x1b[\x20-\x7e]//g;
    s/\x1b//g;
    while (s/[^\x08]\x08//) {}
    s/\x08//g;
    while (s/[^\n]*\r([^\n])/\1/) {}
    s/\r//g;
    s/\x07//g;
    s/\x00//g;
    s/[\x01-\x08\x0b-\x1f\x7f]//g;
    s/\r\n/\n/g;
    s/\r/\n/g;
    next if /^┌── \[/;
    s/\r$//;
    print;
  }
'

{
  printf '=%.0s' {1..60}; echo
  printf " Session: %-10s  Window: %-4s  Pane: %s\n" "$SESSION" "$WINDOW" "$PANE"
  printf " Started: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
  printf '=%.0s' {1..60}; echo
  echo
} >> "$LOG_FILE"

tmux pipe-pane -o \
"exec stdbuf -oL perl -e '$FILTER' >> \"${LOG_FILE}\""

tmux display-message "Logging → $(basename "$LOG_FILE")"
ZSH_LOGGER
 
    chmod +x "$logger_file"
    chown "$TARGET_USER:$TARGET_USER" "$logger_file"
    success "zsh-logger.zsh → $logger_file"


# ── Auto-source from .zshrc when inside tmux ─────────────────────────────────
commandBlock=$(cat << 'EOF'
# -------- Command logger (safe with tmux) --------
zmodload zsh/datetime

_ZLOG_START=0
_ZLOG_CMD=""

_zlog_preexec() {
    [[ -z "$1" ]] && return

    _ZLOG_CMD="$1"
    _ZLOG_START=$EPOCHREALTIME

    local LOG_DIR="${TMUX_LOG_DIR:-$HOME/tmux-logs}"
    #mkdir -p "$LOG_DIR"

    if [[ -n "$TMUX_PANE" ]]; then
        local session window pane
        session=$(tmux display-message -p '#S')
        window=$(tmux display-message -p '#I')
        pane=$(tmux display-message -p '#{pane_id}' | tr -d '%')

        LOG_FILE="$LOG_DIR/tmux-${session}-${window}-${pane}.log"

        printf "[%s] %s\n" \
            "$(strftime '%Y-%m-%d %H:%M:%S' $EPOCHSECONDS)" \
            "$_ZLOG_CMD" >> "$LOG_FILE"
    fi
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _zlog_preexec
EOF
)

    [[ -f "$zshrc" ]] || touch "$zshrc"
    if ! grep -q "zsh-logger.zsh" "$zshrc"; then
        add_to_rc "$zshrc" "command logger" "$c_block"
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
set -g status-right '#{?ZLOG,#[fg=green]LOGGING ON,#[fg=red]LOGGING OFF}'

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

bind-key L run-shell "tmux set-environment -g ZLOG 1; tmux display-message 'Logging ON'"
bind-key S run-shell "tmux set-environment -gu ZLOG; tmux display-message 'Logging OFF'"

# Setup Auto Logging
#set-hook -g after-new-session 'run-shell "~/.tmux/scripts/zsh-logger.zsh"'
#set-hook -g after-new-window 'run-shell "~/.tmux/scripts/zsh-logger.zsh"'
#set-hook -g after-split-window 'run-shell "~/.tmux/scripts/zsh-logger.zsh"'

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

    # ── Setting up tmux aliases ──────────
    tmuxAliases=$(cat << 'EOF'
# -------- Tmux Aliases --------
ktx() {
[[ -n "$TMUX" ]] || { echo "Not inside tmux"; return; }

local session
session=$(tmux display-message -p '#S')

zip_tmux_logs
tmux kill-session -t "$session"
}
    
# -------- Zip tmux logs --------
zip_tmux_logs() {
    local LOG_DIR="${TMUX_LOG_DIR:-$HOME/tmux-logs}"
    [[ -d "$LOG_DIR" ]] || return

    local ts
    ts=$(date "+%Y-%m-%d_%H-%M-%S")

    local zip_file="$HOME/tmux-session-${ts}-logs.zip"

    # zip quietly
    command -v zip >/dev/null || { echo "[!] zip not installed"; return; }

    zip -rq "$zip_file" "$LOG_DIR"
    
    rm -f $LOG_DIR/*

    echo "[+] Logs cleaned & archived → $zip_file"
}
    
    EOF
    )
}