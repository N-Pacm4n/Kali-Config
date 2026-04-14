#!/usr/bin/env bash
# setup.sh — modular pentest setup
# Usage: sudo ./setup.sh [--force] [--category <cat>]

set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"
LIB_DIR="$SCRIPT_DIR/lib"
LOG_DIR="$HOME/.OpsForge-logs"
FORCE=0
FILTER_CATEGORY=""

mkdir -p "$LOG_DIR"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)    FORCE=1 ;;
        --category) FILTER_CATEGORY="$2"; shift ;;
        *) ;;
    esac
    shift
done

source "$LIB_DIR/common.sh"
export MODULES_DIR FORCE

# ── Load all modules ────────────────────────────────────────────────────────────
declare -a MODULE_FILES=()
declare -a MODULE_NAMES=()
declare -a MODULE_DESCS=()
declare -a MODULE_CATS=()
declare -a MODULE_IDS=()

_load_modules() {
    local idx=0
    for f in "$MODULES_DIR"/*.sh; do
        [[ -f "$f" ]] || continue

        # Reset per-module vars before sourcing
        MODULE_NAME=""
        MODULE_DESC=""
        MODULE_CATEGORY="general"

        # Source only the header (first 10 lines) to grab metadata
        eval "$(head -20 "$f" | grep -E '^MODULE_(NAME|DESC|CATEGORY)=')"

        [[ -z "$MODULE_NAME" ]] && continue

        # Filter by category if requested
        if [[ -n "$FILTER_CATEGORY" && "$MODULE_CATEGORY" != "$FILTER_CATEGORY" ]]; then
            continue
        fi

        local mod_id
        mod_id="$(basename "$f" .sh)"

        MODULE_FILES[$idx]="$f"
        MODULE_IDS[$idx]="$mod_id"
        MODULE_NAMES[$idx]="$MODULE_NAME"
        MODULE_DESCS[$idx]="$MODULE_DESC"
        MODULE_CATS[$idx]="$MODULE_CATEGORY"
        (( idx++ ))
    done
}

# ── Print menu ──────────────────────────────────────────────────────────────────
_print_menu() {
    echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║                      OpsForge                    ║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${RESET}\n"

    local prev_cat=""
    for i in "${!MODULE_FILES[@]}"; do
        local cat="${MODULE_CATS[$i]}"
        local mod_id="${MODULE_IDS[$i]}"
        local status=""

        if is_done "$mod_id"; then
            status="${GREEN}[installed]${RESET}"
        elif [[ -f "$STATE_DIR/${mod_id}.failed" ]]; then
            status="${RED}[failed]${RESET}"
        fi

        # Print category header when it changes
        if [[ "$cat" != "$prev_cat" ]]; then
            echo -e "  ${YELLOW}── ${cat^^} ──${RESET}"
            prev_cat="$cat"
        fi

        local num=$(( i + 1 ))
        printf "  ${BOLD}%2d.${RESET} %-20s  %s %b\n" \
            "$num" "${MODULE_NAMES[$i]}" "${MODULE_DESCS[$i]}" "$status"
    done

    echo ""
    echo -e "  ${BOLD}all${RESET}  — run all modules"
    [[ -n "$FILTER_CATEGORY" ]] || \
        echo -e "  ${BOLD}cat:<name>${RESET}  — filter by category (e.g. cat:ad)"
    echo -e "  ${BOLD}Enter${RESET} — exit"
    echo ""
}

# ── Run a single module ─────────────────────────────────────────────────────────
_run_module() {
    local mod_file="$1"
    local mod_id="$2"
    local mod_name="${3:-$mod_id}"

    if is_done "$mod_id" && [[ "$FORCE" -eq 0 ]]; then
        warn "'$mod_name' already installed. Use --force to re-run."
        return 0
    fi

    export MODULE_LOG="$LOG_DIR/${mod_id}_$(date +%Y%m%d_%H%M%S).log"
    header "Installing: $mod_name"
    info "Log → $MODULE_LOG"

    # Source common + module, then call install()
    (
        set -eo pipefail
        source "$LIB_DIR/common.sh"
        source "$mod_file"
        get_target_user
        install
    ) 2>&1 | tee -a "$MODULE_LOG"

    if [[ "${PIPESTATUS[0]}" -eq 0 ]]; then
        mark_done "$mod_id"
        success "'$mod_name' installed successfully."
        return 0
    else
        mark_failed "$mod_id"
        fail "'$mod_name' failed. Check log: $MODULE_LOG"
        if confirm "Continue with remaining modules? (y/N)"; then
            return 1
        else
            exit 1
        fi
    fi
}

# ── Parse selection string → indices ────────────────────────────────────────────
_parse_selection() {
    local input="$1"
    local -a selected=()

    # Replace commas with spaces, then iterate
    for token in ${input//,/ }; do
        if [[ "$token" =~ ^[0-9]+$ ]]; then
            local idx=$(( token - 1 ))
            if [[ $idx -ge 0 && $idx -lt ${#MODULE_FILES[@]} ]]; then
                selected+=("$idx")
            else
                warn "Invalid number: $token (max ${#MODULE_FILES[@]})"
            fi
        fi
    done

    echo "${selected[@]}"
}

# ── Main loop ───────────────────────────────────────────────────────────────────
main() {
    _load_modules

    if [[ ${#MODULE_FILES[@]} -eq 0 ]]; then
        fail "No modules found in $MODULES_DIR"
        exit 1
    fi

    while true; do
        _print_menu
        read -r -p "$(echo -e "${BOLD}Select [1-${#MODULE_FILES[@]}], all, cat:<name>, or Enter to exit:${RESET} ")" selection

        # Exit on empty input
        [[ -z "$selection" ]] && { echo -e "\n${GREEN}Goodbye.${RESET}\n"; exit 0; }

        # Category filter
        if [[ "$selection" == cat:* ]]; then
            FILTER_CATEGORY="${selection#cat:}"
            _load_modules
            continue
        fi

        # Clear category filter
        if [[ "$selection" == "all-categories" || "$selection" == "cat:" ]]; then
            FILTER_CATEGORY=""
            _load_modules
            continue
        fi

        # Run all
        if [[ "$selection" == "all" ]]; then
            for i in "${!MODULE_FILES[@]}"; do
                _run_module "${MODULE_FILES[$i]}" "${MODULE_IDS[$i]}" "${MODULE_NAMES[$i]}"
            done
            continue
        fi

        # Run selected numbers
        local -a indices
        read -ra indices <<< "$(_parse_selection "$selection")"

        if [[ ${#indices[@]} -eq 0 ]]; then
            warn "No valid selection. Try again."
            continue
        fi

        for idx in "${indices[@]}"; do
            _run_module "${MODULE_FILES[$idx]}" "${MODULE_IDS[$idx]}" "${MODULE_NAMES[$idx]}"
        done
    done
}

main