#!/usr/bin/env bash
MODULE_NAME="Terminal Setup"
MODULE_DESC="Aliases, history hardening, clean scripts, configure proxychains, Configure SSH"
MODULE_CATEGORY="general"

install() {
    # Unlimited history with timestamps
    local hist_block
    hist_block='# History hardening
export HISTSIZE=-1
export HISTFILESIZE=-1
export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S  "
export HISTCONTROL=ignoredups
setopt HIST_IGNORE_ALL_DUPS 2>/dev/null || true   # zsh
setopt INC_APPEND_HISTORY    2>/dev/null || true
setopt SHARE_HISTORY         2>/dev/null || true'

    # OPSEC aliases
    local alias_block
    alias_block='# Aliases
alias curl="curl -s -A \"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36\""
alias wget="wget -q"
alias clean-history="history -c; history -w; cat /dev/null > ~/.bash_history; cat /dev/null > ~/.zsh_history; echo \"[+] History cleared\""
alias clean-tmp="rm -rf /tmp/* /var/tmp/* 2>/dev/null; echo \"[+] /tmp cleared\""
alias clean-logs="truncate -s0 /var/log/auth.log /var/log/syslog 2>/dev/null; echo \"[+] Logs cleared\""
alias opsec-clean="clean-history && clean-tmp && echo \"[+] OPSEC clean done\""'

    for rc in "$USER_HOME/.bashrc" "$USER_HOME/.zshrc"; do
        [[ -f "$rc" ]] || touch "$rc"
        add_to_rc "$rc" "history-hardening" "$hist_block"
        add_to_rc "$rc" "opsec-aliases" "$alias_block"
        chown "$TARGET_USER:$TARGET_USER" "$rc"
        success "OPSEC config added to $rc"
    done

    # SSH config
    local ssh_dir="$USER_HOME/.ssh"
    local ssh_conf="$ssh_dir/config"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    if ! grep -q "kali-setup: ssh-defaults" "$ssh_conf" 2>/dev/null; then
        cat >> "$ssh_conf" <<'EOF'

# >>> kali-setup: ssh-defaults >>>
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 10
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m

# <<< kali-setup: ssh-defaults <<<
EOF
        chmod 600 "$ssh_conf"
        chown "$TARGET_USER:$TARGET_USER" "$ssh_conf"
        success "SSH config written to $ssh_conf"
    fi

    # proxychains4 config
    if command -v proxychains4 &>/dev/null || apt_install proxychains4; then
        local pc_conf="/etc/proxychains4.conf"
        if [[ -f "$pc_conf" ]]; then
            # socks5 127.0.0.1 1080 are set
            grep -q "socks5.*1080" "$pc_conf" || echo "socks5  127.0.0.1  1080" >> "$pc_conf"
            success "proxychains4 configured"
        fi
    fi
}