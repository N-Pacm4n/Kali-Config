#!/usr/bin/env bash
MODULE_NAME="Wordlists"
MODULE_DESC="SecLists, rockyou unzipped, custom RT lists"
MODULE_CATEGORY="recon"

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

    # Symlink for convenience
    [[ -L /usr/share/wordlists/seclists ]] || \
        ln -sf "$wl_dir/SecLists" /usr/share/wordlists/seclists \
        && success "Symlink: /usr/share/wordlists/seclists → $wl_dir/SecLists"

    # ── rockyou.txt ─────────────────────────────────────────────────────────────
    if [[ ! -f "$wl_dir/rockyou.txt" ]]; then
        if [[ -f /usr/share/wordlists/rockyou.txt.gz ]]; then
            info "Unzipping rockyou.txt..."
            gzip -dk /usr/share/wordlists/rockyou.txt.gz >> "$MODULE_LOG" 2>&1
            cp /usr/share/wordlists/rockyou.txt "$wl_dir/rockyou.txt"
            success "rockyou.txt → $wl_dir/rockyou.txt"
        elif [[ -f /usr/share/wordlists/rockyou.txt ]]; then
            cp /usr/share/wordlists/rockyou.txt "$wl_dir/rockyou.txt"
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

    # ── Custom red team lists ────────────────────────────────────────────────────
    info "Downloading targeted red team wordlists..."

    declare -A extra_lists=(
        ["common-passwords-win.txt"]="https://raw.githubusercontent.com/danielmiessler/SecLists/master/Passwords/Common-Credentials/common-passwords-win.txt"
        ["top-usernames-shortlist.txt"]="https://raw.githubusercontent.com/danielmiessler/SecLists/master/Usernames/top-usernames-shortlist.txt"
        ["subdomains-top1mil-5000.txt"]="https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/DNS/subdomains-top1million-5000.txt"
    )

    mkdir -p "$wl_dir/custom"
    for fname in "${!extra_lists[@]}"; do
        [[ -f "$wl_dir/custom/$fname" ]] && continue
        curl -fsSL "${extra_lists[$fname]}" -o "$wl_dir/custom/$fname" >> "$MODULE_LOG" 2>&1 \
            && success "Downloaded: $fname" \
            || warn "Failed: $fname"
    done

    chown -R "$TARGET_USER:$TARGET_USER" "$wl_dir"
    success "Wordlists ready in $wl_dir"
}