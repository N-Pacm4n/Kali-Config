#!/usr/bin/env bash
# auto-log.sh — drop-in replacement for N-Pacm4n/Kali-Config auto-log.sh
#
# Fixes: ^H, zsh-syntax-highlighting, zsh-autosuggestions, OSC sequences,
#        DCS, bracketed paste markers, ZLE cursor codes, and all other
#        control characters that survive a basic ANSI color strip.
#
# Uses tmux pipe-pane (no extra background processes per pane).
# Safe to call on new-session, after-new-window, after-split-window.

LOG_DIR="${TMUX_LOG_DIR:-$HOME/tmux-logs}"
mkdir -p "$LOG_DIR"

# ── Build a unique filename: session-window-pane-timestamp ─────────────────────
SESSION=$(tmux display-message -p '#S')
WINDOW=$(tmux display-message  -p '#I')
PANE=$(tmux display-message    -p '#P')
TIMESTAMP=$(date "+%Y-%m-%d_%H-%M-%S")

LOG_FILE="$LOG_DIR/tmux-${SESSION}-w${WINDOW}-p${PANE}-${TIMESTAMP}.log"

# ── The filter — handles everything zsh plugins throw at the terminal ──────────
#
# Order matters. We process left to right:
#   1. OSC sequences  \e]...\e\\ or \e]...\x07   (window titles, hyperlinks, colour schemes)
#   2. DCS sequences  \eP...\e\\                  (tmux passthrough, Sixel)
#   3. CSI sequences  \e[...X  (colours, cursor, erase, SGR, DECSET, etc.)
#   4. Standalone ESC sequences  \e[single char]  (cursor keys, SS2/SS3, RIS, etc.)
#   5. ^H backspace   \x08  — zsh-syntax-highlighting redraws by backspacing
#   6. ^M carriage return  \r
#   7. ^G bell  \x07
#   8. Bracketed paste markers  \e[?2004h / \e[?2004l  (caught by rule 3, but belt-and-braces)
#   9. NUL bytes \x00
#  10. Any remaining non-printable non-whitespace bytes
#
# We use perl because sed's \x escapes are not portable across BSD/GNU,
# and perl is always present on Kali. stdbuf -oL keeps lines flushing live.

FILTER='
  use strict;
  $| = 1;                    # flush every line
  while (<STDIN>) {
    # 1. OSC  \e ] ... ( \e \\ | \x07 )
    s/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)//g;
    # 2. DCS  \e P ... \e \\
    s/\x1b[P][^\x1b]*\x1b\\//g;
    # 3. CSI  \e [ ... (final byte 0x40-0x7E)
    s/\x1b\[[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]//g;
    # 4. Standalone two-byte ESC sequences  \e + one char (0x20-0x7E)
    s/\x1b[\x20-\x7e]//g;
    # 5. Bare ESC (anything left)
    s/\x1b//g;
    # 6. Backspace  ^H  — remove char before each ^H (zsh-syntax-highlighting)
    while (s/[^\x08]\x08//) {}
    s/\x08//g;               # leading ^H with nothing before it
    # 7. Carriage return (keep last segment only, like a real terminal would)
    while (s/[^\n]*\r([^\n])/\1/) {}
    s/\r//g;
    # 8. Bell
    s/\x07//g;
    # 9. NUL
    s/\x00//g;
    # 10. Any remaining C0 controls except \t \n
    s/[\x01-\x08\x0b-\x1f\x7f]//g;
    print if /\S/;           # skip lines that became pure whitespace
  }
'

# ── Write log header ───────────────────────────────────────────────────────────
{
  printf '=%.0s' {1..60}; echo
  printf " Session: %-10s  Window: %-4s  Pane: %s\n" "$SESSION" "$WINDOW" "$PANE"
  printf " Started: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
  printf " Log:     %s\n" "$LOG_FILE"
  printf '=%.0s' {1..60}; echo
  echo
} >> "$LOG_FILE"

# ── Start logging ──────────────────────────────────────────────────────────────
# pipe-pane -o = only pipe output (not input echoes), preventing double logging.
# stdbuf -oL = line-buffer perl's stdout so writes happen promptly.
tmux pipe-pane -o \
  "exec stdbuf -oL perl -e '$FILTER' >> '$LOG_FILE'"

tmux display-message "Logging → $(basename "$LOG_FILE")"