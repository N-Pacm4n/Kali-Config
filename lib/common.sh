#!/usr/bin/env bash
# lib/common.sh — shared helpers for all modules

# ── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Print helpers ───────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[*]${RESET} $*"; }
success() { echo -e "${GREEN}[+]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
fail()    { echo -e "${RED}[-]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════${RESET}\n"; }

# ── Confirm prompt ──────────────────────────────────────────────────────────────
confirm() {
    local prompt="${1:-Proceed? (y/N)}"
    read -r -p "$(echo -e "${YELLOW}[?]${RESET} ${prompt} ")" ans
    case "$ans" in [Yy]|[Yy][Ee][Ss]) return 0 ;; *) return 1 ;; esac
}

# ── Root check ──────────────────────────────────────────────────────────────────
require_root() {
    [[ "${EUID:-0}" -eq 0 ]] || { fail "Module requires root. Run with sudo."; exit 1; }
}

# ── Determine invoking user ─────────────────────────────────────────────────────
get_target_user() {
    TARGET_USER="${SUDO_USER:-$USER}"
    USER_HOME=$(eval echo "~$TARGET_USER")
    export TARGET_USER USER_HOME
}

# ── apt wrapper — quiet, logged ─────────────────────────────────────────────────
apt_install() {
    info "apt install: $*"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$@" \
        >> "$MODULE_LOG" 2>&1 \
        && success "Installed: $*" \
        || { fail "apt failed for: $*"; return 1; }
}

# ── State tracking ──────────────────────────────────────────────────────────────
STATE_DIR="${HOME}/.opsforge"
mkdir -p "$STATE_DIR"

is_done() {
    local mod="$1"
    [[ -f "$STATE_DIR/${mod}.done" ]]
}

mark_done() {
    local mod="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$STATE_DIR/${mod}.done"
}

mark_failed() {
    local mod="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$STATE_DIR/${mod}.failed"
}

clear_state() {
    local mod="$1"
    rm -f "$STATE_DIR/${mod}.done" "$STATE_DIR/${mod}.failed"
}

# ── Module dependency resolver ──────────────────────────────────────────────────
require_module() {
    local mod="$1"
    local mod_file="$MODULES_DIR/${mod}.sh"

    if is_done "$mod"; then
        return 0
    fi

    if [[ ! -f "$mod_file" ]]; then
        fail "Required module not found: $mod"
        return 1
    fi

    warn "Module '$mod' is required. Installing it first..."
    _run_module "$mod_file" "$mod"
}

# ── GitHub latest release tag ───────────────────────────────────────────────────
github_latest_release() {
    # Usage: github_latest_release "owner/repo"
    local repo="$1"
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
        | grep '"tag_name"' \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

# ── Download binary from GitHub releases ────────────────────────────────────────
github_download() {
    # Usage: github_download "owner/repo" "pattern" "/dest/path"
    local repo="$1" pattern="$2" dest="$3"
    local tag
    tag=$(github_latest_release "$repo")
    local url
    url=$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
        | grep "browser_download_url" \
        | grep -i "$pattern" \
        | head -1 \
        | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/')
    [[ -z "$url" ]] && { fail "Could not find release asset matching: $pattern"; return 1; }
    info "Downloading $repo ($tag) → $dest"
    curl -fsSL "$url" -o "$dest" >> "$MODULE_LOG" 2>&1
}

# ── Add block to rc file (idempotent) ───────────────────────────────────────────
add_to_rc() {
    # Usage: add_to_rc "$HOME/.zshrc" "block-id" "content"
    local rc_file="$1" block_id="$2" content="$3"
    local marker_start="# >>> OpsForge: ${block_id} >>>"
    local marker_end="# <<< OpsForge: ${block_id} <<<"

    if grep -qF "$marker_start" "$rc_file" 2>/dev/null; then
        # Replace existing block
        awk -v s="$marker_start" -v e="$marker_end" -v c="${marker_start}\n${content}\n${marker_end}" \
            'BEGIN{p=1} $0==s{print c; p=0} $0==e{p=1; next} p{print}' \
            "$rc_file" > "${rc_file}.tmp" && mv "${rc_file}.tmp" "$rc_file"
    else
        printf '\n%s\n%s\n%s\n' "$marker_start" "$content" "$marker_end" >> "$rc_file"
    fi
}