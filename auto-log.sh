#!/usr/bin/env bash

LOG_DIR="$HOME/tmux-logs"
mkdir -p "$LOG_DIR"

timestamp=$(date "+%Y-%m-%d_%H-%M-%S")
session=$(tmux display-message -p '#S')
window=$(tmux display-message -p '#I')
pane=$(tmux display-message -p '#P')
filename="tmux-${session}-${window}-${pane}-${timestamp}.log"
log_file="$LOG_DIR/$filename"

ansifilter_installed() {
    command -v ansifilter >/dev/null 2>&1
}

pipe_with_ansifilter() {
    tmux pipe-pane -o "exec cat - | ansifilter >> '$log_file'"
}

pipe_with_sed_linux() {
    local ansi_codes='\x1B\[[0-9;]*[mGKHF]'
    tmux pipe-pane -o "exec cat - | stdbuf -oL sed -r \"s/$ansi_codes//g\" >> '$log_file'"
}

start_logging() {
    if ansifilter_installed; then
        pipe_with_ansifilter
    else
        pipe_with_sed_linux
    fi
    tmux display-message "Started logging to $filename"
}

start_logging

