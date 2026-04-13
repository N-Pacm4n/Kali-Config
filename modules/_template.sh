#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# TEMPLATE — copy this file to modules/NN_mytool.sh and fill in the blanks.
#
# Naming: prefix with NN_ (e.g. 10_mytool.sh) to control menu order.
# The three MODULE_* lines MUST be at the top — setup.sh reads them via head.
# ─────────────────────────────────────────────────────────────────────────────
MODULE_NAME="My Tool"
MODULE_DESC="One-line description shown in menu"
MODULE_CATEGORY="recon"   # setup | recon | ad | infra | web | general

install() {
    # require_root          # uncomment if root is needed
    # require_module "01_go"  # uncomment if another module must run first

    # ── Example: install via apt ────────────────────────────────────────────────
    # apt_install mytool

    # ── Example: install via pip / pipx ─────────────────────────────────────────
    # pip3 install mytool --break-system-packages >> "$MODULE_LOG" 2>&1

    # ── Example: download latest GitHub release binary ───────────────────────────
    # github_download "owner/repo" "linux_amd64" "/tmp/mytool"
    # install -m 755 /tmp/mytool /usr/local/bin/mytool

    # ── Example: go install ───────────────────────────────────────────────────────
    # export GOROOT=/usr/local/go GOPATH="$USER_HOME/go"
    # export PATH="$PATH:$GOROOT/bin:$GOPATH/bin"
    # sudo -u "$TARGET_USER" env GOROOT="$GOROOT" GOPATH="$GOPATH" PATH="$PATH" \
    #     go install github.com/owner/repo@latest >> "$MODULE_LOG" 2>&1

    # ── Example: add shell alias / env var ──────────────────────────────────────
    # local block='alias mytool="mytool --flag"'
    # for rc in "$USER_HOME/.bashrc" "$USER_HOME/.zshrc"; do
    #     [[ -f "$rc" ]] || touch "$rc"
    #     add_to_rc "$rc" "mytool" "$block"
    # done

    success "My Tool installed"
}