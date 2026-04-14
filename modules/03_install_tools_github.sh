#!/usr/bin/env bash
MODULE_NAME="Toolkit"
MODULE_DESC="SecLists, rockyou unzipped, certipy, netexec"
MODULE_CATEGORY="general"

install() {
    require_root

    local wl_dir="/opt/wordlists"
    mkdir -p "$wl_dir"

    # ── SecLists ────────────────────────────────────────────────────────────────
    if [[ -d "$wl_dir/SecLists/.git" ]]; then
        info "SecLists already cloned. Pulling updates..."
        git -C "$wl_dir/SecLists" pull >> "$MODULE_LOG" 2>&1 \
            && success "SecLists updated" \
            || warn "SecLists pull failed"
    else
        info "Cloning SecLists (this may take a while)..."
        git clone --depth=1 \
            https://github.com/danielmiessler/SecLists.git \
            "$wl_dir/SecLists" >> "$MODULE_LOG" 2>&1 \
            && success "SecLists → $wl_dir/SecLists" \
            || warn "SecLists clone failed"
    fi

    # ── rockyou.txt ─────────────────────────────────────────────────────────────
    if [[ ! -f "$wl_dir/rockyou.txt" ]]; then
        if [[ -f /usr/share/wordlists/rockyou.txt.gz ]]; then
            info "Unzipping rockyou.txt..."
            gzip -dk /usr/share/wordlists/rockyou.txt.gz >> "$MODULE_LOG" 2>&1
            mv /usr/share/wordlists/rockyou.txt "$wl_dir/rockyou.txt"
            success "rockyou.txt → $wl_dir/rockyou.txt"
        elif [[ -f /usr/share/wordlists/rockyou.txt ]]; then
            mv /usr/share/wordlists/rockyou.txt "$wl_dir/rockyou.txt"
            success "rockyou.txt copied"
        else
            info "Downloading rockyou.txt..."
            curl -fsSL \
                "https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt" \
                -o "$wl_dir/rockyou.txt" >> "$MODULE_LOG" 2>&1 \
                && success "rockyou.txt downloaded" \
                || warn "rockyou download failed"
        fi

        [[ -L /usr/share/wordlists/rockyou.txt ]] || \
            ln -sf "$wl_dir/rockyou.txt" /usr/share/wordlists/rockyou.txt 2>/dev/null || true
    else
        info "rockyou.txt already present"
    fi

    chown -R "$TARGET_USER:$TARGET_USER" "$wl_dir"
    success "Wordlists ready in $wl_dir"

    # ── Tools ────────────────────────────────────────────────────────────────
    
    # Update netexec
    info "Installing latest version of netexec"
    rm -rf /usr/bin/netexec /usr/bin/nxc
    pipx install git+https://github.com/Pennyw0rth/NetExec
    success "Netexec latest version installed"

    # Install Certipy-ad
    info "Installing Certipy"
    pipx install certipy-ad
    Success "Certipy installed"

}