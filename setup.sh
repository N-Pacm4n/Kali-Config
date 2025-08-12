#!/usr/bin/env bash
# kali-setup.sh
# Purpose: update Kali, install unzip, deploy tmux.conf, chown /opt, install latest Go, configure shells, optionally enable passwordless sudo.
# Usage: sudo ./kali-setup.sh
set -o errexit
set -o nounset
set -o pipefail

# Error handler
_err() {
  local lineno=$1
  local code=$2
  echo "ERROR: script failed at line ${lineno} with exit code ${code}" >&2
  exit "${code}"
}
trap ' _err ${LINENO} $?' ERR

# Helpers
info(){ echo -e "\e[34m[INFO]\e[0m $*"; }
warn(){ echo -e "\e[33m[WARN]\e[0m $*"; }
fail(){ echo -e "\e[31m[ERROR]\e[0m $*" >&2; exit 1; }

confirm() {
  # $1 = prompt, default "y/N"
  local prompt="${1:-Proceed? (y/N)}"
  read -r -p "$prompt " ans
  case "$ans" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

# Determine invoking user (non-root)
if [[ "${EUID:-0}" -ne 0 ]]; then
  fail "Please run this script with sudo or as root: sudo ./kali-setup.sh"
fi

TARGET_USER="${SUDO_USER:-}"
if [[ -z "$TARGET_USER" ]]; then
  warn "Could not determine non-root invoking user. Defaulting TARGET_USER to 'root'."
  TARGET_USER="root"
fi
#USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "/root")"
USER_HOME=$(eval echo "~$SUDO_USER")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info "Target non-root user: $TARGET_USER"
info "Target home directory: $USER_HOME"
info "Script directory: $SCRIPT_DIR"

########################
# 1) Update system
########################
update_upgrade() {
    info "Updating package lists and upgrading packages (apt-get update && apt-get upgrade -y)..."
    apt-get update -y
    #DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    info "System update complete."
}

###############################
# 2) Terminal Preference
###############################
setup_xfce4_terminal() {
    uid=$(id -u "$TARGET_USER")

    info "Installing XFCE4 Terminal..."
    sudo apt-get update -y
    sudo apt-get install -y xfce4-terminal

    # Setting up config via properties
    sudo -u "$TARGET_USER" env DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" bash -c '
        xfconf-query -c xfce4-terminal -p /background-darkness -s 1.0 --create -t double
        xfconf-query -c xfce4-terminal -p /background-mode -s TERMINAL_BACKGROUND_SOLID --create -t string
        xfconf-query -c xfce4-terminal -p /color-background -s "#000000000000" --create -t string
        xfconf-query -c xfce4-terminal -p /color-background-vary -s false --create -t bool
        xfconf-query -c xfce4-terminal -p /color-bold -t string --create -s ""
        xfconf-query -c xfce4-terminal -p /color-bold-is-bright -s true --create -t bool
        xfconf-query -c xfce4-terminal -p /color-bold-use-default -s true --create -t bool
        xfconf-query -c xfce4-terminal -p /color-cursor -s "#FFFAF4" --create -t string
        xfconf-query -c xfce4-terminal -p /color-cursor-foreground -t string --create -s ""
        xfconf-query -c xfce4-terminal -p /color-cursor-use-default -s false --create -t bool
        xfconf-query -c xfce4-terminal -p /color-foreground -s "#FFFAF4" --create -t string
        xfconf-query -c xfce4-terminal -p /color-palette -s "#232323;#FF000F;#8CE10B;#FFB900;#008DF8;#6D43A6;#00D8EB;#FFFFFF;#444444;#FF2740;#ABE15B;#FFD242;#0092FF;#9A5FEB;#67FFF0;#FFFFFF" --create -t string
        xfconf-query -c xfce4-terminal -p /color-selection-use-default -s true --create -t bool
        xfconf-query -c xfce4-terminal -p /color-use-theme -s false --create -t bool
        xfconf-query -c xfce4-terminal -p /font-name -s "Fira Code weight=450 10" --create -t string
        xfconf-query -c xfce4-terminal -p /font-use-system -s false --create -t bool
        xfconf-query -c xfce4-terminal -p /misc-borders-default -s true --create -t bool
        xfconf-query -c xfce4-terminal -p /misc-cursor-blinks -s true --create -t bool
        xfconf-query -c xfce4-terminal -p /misc-cursor-shape -s TERMINAL_CURSOR_SHAPE_IBEAM --create -t string
        xfconf-query -c xfce4-terminal -p /misc-maximize-default -s true --create -t bool
        xfconf-query -c xfce4-terminal -p /misc-menubar-default -s false --create -t bool
        xfconf-query -c xfce4-terminal -p /misc-show-unsafe-paste-dialog -s false --create -t bool
        xfconf-query -c xfce4-terminal -p /scrolling-unlimited -s true --create -t bool
        xfconf-query -c xfce4-terminal -p /tab-activity-color -s "#aa0000" --create -t string
        xfconf-query -c xfce4-terminal -p /title-mode -s TERMINAL_TITLE_HIDE --create -t string
    '
  
    # Set xfce-terminal as default
    local helpers_file="/etc/xdg/xfce4/helpers.rc"

    info "Setting xfce4-terminal as default terminal..."
    mkdir -p "$(dirname "$helpers_file")"

     if grep -q "^TerminalEmulator=" "$helpers_file" 2>/dev/null; then
        sed -i 's|^TerminalEmulator=.*|TerminalEmulator=xfce4-terminal|' "$helpers_file"
    else
        echo "TerminalEmulator=xfce4-terminal" >> "$helpers_file"
    fi

    info "Default terminal set to xfce4-terminal."
}

#####################################
# 3) Default to ZSH & Datetime
#####################################
setup_zsh_with_datetime_prompt() {
    local zsh_path="/usr/bin/zsh"
    local zshrc="$USER_HOME/.zshrc"
    local original_line="PROMPT=\$'%F{%(#.blue.green)}┌──\${debian_chroot:+(\$debian_chroot)─}\${VIRTUAL_ENV:+(\$(basename \$VIRTUAL_ENV))─}(%B%F{%(#.red.blue)}%n'\$prompt_symbol\$'%m%b%F{%(#.blue.green)})-[%B%F{reset}%(6~.%-1~/…/%4~.%5~)%b%F{%(#.blue.green)}]\n└─%B%(#.%F{red}#.%F{blue}$)%b%F{reset} '"
    local new_line="PROMPT=\$'%F{%(#.blue.green)}┌── [%F{yellow}%D{%Y-%m-%d %H:%M:%S}%f] \${debian_chroot:+(\$debian_chroot)─}\${VIRTUAL_ENV:+(\$(basename \$VIRTUAL_ENV))─}(%B%F{%(#.red.blue)}%n'\$prompt_symbol\$'%m%b%F{%(#.blue.green)})-[%B%F{reset}%(6~.%-1~/…/%4~.%5~)%b%F{%(#.blue.green)}]\n└─%B%(#.%F{red}#.%F{blue}$)%b%F{reset} '"

    new_prompt=$(cat <<'EOF'
PROMPT=$'%F{%(#.blue.green)}┌── [%F{yellow}%D{%Y-%m-%d %H:%M:%S}%f] ${debian_chroot:+($debian_chroot)─}${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV))─}(%B%F{%(#.red.blue)}%n'$prompt_symbol$'%m%b%F{%(#.blue.green)})-[%B%F{reset}%(6~.%-1~/…/%4~.%5~)%b%F{%(#.blue.green)}]\n└─%B%(#.%F{red}#.%F{blue}$)%b%F{reset} '
EOF
)

    info "Checking if Zsh is installed..."
    if ! command -v zsh &>/dev/null; then
        info "Zsh not found. Installing..."
        sudo apt-get update -y && sudo apt-get install -y zsh
    else
        info "Zsh is already installed."
    fi

    info "Checking current default shell..."
    if [[ "$SHELL" != "$zsh_path" ]]; then
        info "Changing default shell to Zsh..."
        if chsh -s "$zsh_path"; then
            info "Default shell changed to Zsh."
        else
            error "Failed to change default shell. You may need to log out and back in."
        fi
    else
        info "Zsh is already the default shell."
    fi

    info "Configuring Zsh prompt with date and time..."
    if [[ -f "$zshrc" ]]; then
	if grep -Fq "%D{%Y-%m-%d %H:%M:%S}" "$zshrc"; then
            info "Zsh prompt already contains date/time."
            return 0
        fi
        if grep -Fq "$original_line" "$zshrc"; then
	    cp "$zshrc" "$zshrc.bak.$(date +%s)"
	     sed -i "/twoline)/,/;;/c\\
        twoline)\\
            $new_prompt\\
            ;;\
" "$zshrc"
	    info "Zsh prompt updated with date/time."
        else
            warn "Original PROMPT line not found. Skipping."
        fi
    fi
}

########################
# 4) Configuring TMUX
########################
setup_tmux() {
    local target_user=${SUDO_USER:-$USER}
    local tmux_conf_src="$SCRIPT_DIR/tmux.conf"
    local tmux_conf_dest="$USER_HOME/.tmux.conf"
    local auto_log_src="$SCRIPT_DIR/auto-log.sh"
    local tpm_dir="$USER_HOME/.tmux/plugins/tpm"
    local tmux_scripts_dir="$USER_HOME/.tmux/scripts"
    local tmux_logs_dir="$USER_HOME/tmux-logs"

    info "Installing tmux and git..."
    if ! sudo apt-get install -y tmux git; then
        fail "Failed to install tmux or git."
        return 1
    fi

    # Copy tmux.conf
    if [[ -f "$tmux_conf_src" ]]; then
        cp "$tmux_conf_src" "$tmux_conf_dest" && chown "$target_user":"$target_user" "$tmux_conf_dest"
        info "tmux.conf copied to $tmux_conf_dest"
    else
        warn "tmux.conf not found in script directory. Skipping."
    fi

    # Install TPM
    if [[ ! -d "$tpm_dir" ]]; then
        if sudo -u "$target_user" git clone https://github.com/tmux-plugins/tpm "$tpm_dir"; then
            info "TPM installed at $tpm_dir"
        else
            fail "Failed to clone TPM."
            return 1
        fi
    else
        info "TPM already installed."
    fi

    # Add tmux-resurrect plugin if not present
    #if [[ -f "$tmux_conf_dest" ]] && ! grep -q "tmux-plugins/tmux-resurrect" "$tmux_conf_dest"; then
    #    echo "set -g @plugin 'tmux-plugins/tmux-resurrect'" >> "$tmux_conf_dest"
    #    info "Added tmux-resurrect plugin to tmux.conf"
    #fi

    # Create logs directory
    mkdir -p "$tmux_logs_dir" && chown "$target_user":"$target_user" "$tmux_logs_dir"
    info "Created tmux logs directory at $tmux_logs_dir"

    # Copy auto-log.sh
    mkdir -p "$tmux_scripts_dir" && chown "$target_user":"$target_user" "$tmux_scripts_dir"
    if [[ -f "$auto_log_src" ]]; then
        cp "$auto_log_src" "$tmux_scripts_dir/auto-log.sh"
        chmod +x "$tmux_scripts_dir/auto-log.sh"
        chown "$target_user":"$target_user" "$tmux_scripts_dir/auto-log.sh"
        info "auto-log.sh copied to $tmux_scripts_dir"
    else
        warn "auto-log.sh not found in script directory. Skipping."
    fi

    # Install tmux plugins
    #info "Installing tmux plugins via TPM..."
    #if ! sudo -u "$target_user" bash -c "
    #    tmux start-server
    #    tmux new-session -d
    #    $tpm_dir/bin/install_plugins
    #    tmux kill-server
    #"; then
    #    error "Failed to install tmux plugins."
    #    return 1
    #fi

    info "Tmux setup complete."
}


########################
# 6) Take ownership of /opt
########################
be_owner() {
    info "You asked to take ownership of /opt. This will chown -R /opt -> ${TARGET_USER}:${TARGET_USER}."
    warn "This can affect packages or services that expect /opt owned by root. Proceed only if you know the consequences."
    if confirm "Take ownership of /opt? This runs: chown -R ${TARGET_USER}:${TARGET_USER} /opt (y/N)"; then
      if [[ -d /opt ]]; then
        info "Changing ownership of /opt (recursive)..."
        chown -R "${TARGET_USER}:${TARGET_USER}" /opt
        info "Ownership of /opt changed to ${TARGET_USER}:${TARGET_USER}."
      else
        warn "/opt does not exist; skipping chown."
    fi
    else
        info "Skipping chown of /opt as requested."
    fi
}

########################
# 7) Install latest Go
########################
install_go() {
  info "Installing latest Go for this machine..."

  # Determine architecture
  arch="$(uname -m)"
  case "$arch" in
    x86_64) go_arch="amd64" ;;
    aarch64|arm64) go_arch="arm64" ;;
    armv7l|armv6l) go_arch="armv6l" ;; # older ARM - may not exist for very new Go
    *) fail "Unsupported architecture: $arch" ;;
  esac

  # Get latest version string from go.dev
  if ! command -v curl &>/dev/null; then
    info "curl not found; installing curl"
    apt-get install -y curl
  fi

  info "Fetching latest Go version from go.dev..."
  latest_ver="$(curl -fsSL https://go.dev/VERSION?m=text | head -n 1)" || fail "Failed to fetch latest Go version."
  # e.g., latest_ver="go1.21.5"
  info "Latest Go version: $latest_ver"

  TARFILE="${latest_ver}.linux-${go_arch}.tar.gz"
  DOWNLOAD_URL="https://go.dev/dl/${TARFILE}"

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  info "Downloading $DOWNLOAD_URL ..."
  curl -fsSL -o "$tmpdir/$TARFILE" "$DOWNLOAD_URL" || fail "Failed to download Go archive."

  # Remove old Go install if exists
  if [[ -d /usr/local/go ]]; then
    info "Removing existing /usr/local/go"
    rm -rf /usr/local/go
  fi

  info "Extracting ${TARFILE} to /usr/local..."
  tar -C /usr/local -xzf "$tmpdir/$TARFILE" || fail "Failed to extract Go tarball."

  info "Go installed to /usr/local/go"
  # ensure ownership and permissions
  chown -R $TARGET_USER:$TARGET_USER /usr/local/go
  info "Ownership of /usr/local/go set to current user."
}

########################
# 7) Configure go variables in shell rc files
########################
add_or_replace_profile_block() {
  #$1 = target file (absolute path)
  local profile="$1"
  local marker_start="# >>> go env configuration (managed by kali-setup.sh) >>>"
  local marker_end="# <<< go env configuration (managed by kali-setup.sh) <<<"
  local goroot="/usr/local/go"
  local gopath="${USER_HOME}/go"
  local block
  block="$marker_start
export GOROOT=$goroot
export GOPATH=$gopath
export PATH=\$PATH:\$GOROOT/bin:\$GOPATH/bin
$marker_end"

  # create file if missing
  if [[ ! -f "$profile" ]]; then
    touch "$profile"
    chown "$TARGET_USER":"$TARGET_USER" "$profile"
  fi

  # If markers exist, replace block. Otherwise append.
  if grep -qF "$marker_start" "$profile" 2>/dev/null; then
    info "Updating existing Go environment block in $profile"
    # Use awk to replace between markers
    awk -v start="$marker_start" -v end="$marker_end" -v newblock="$block" '
      BEGIN{inside=0}
      $0==start{print newblock; inside=1; next}
      $0==end{inside=0; next}
      { if (!inside) print }
    ' "$profile" > "${profile}.tmp" && mv "${profile}.tmp" "$profile"
  else
    info "Appending Go environment block to $profile"
    printf "\n%s\n" "$block" >> "$profile"
  fi
  chown "$TARGET_USER":"$TARGET_USER" "$profile"

}

configure_rc_files() {
info "Configuring Go environment in shell rc files for user $TARGET_USER..."
add_or_replace_profile_block "${USER_HOME}/.bashrc"
if [[ -f "${USER_HOME}/.zshrc" ]]; then
  add_or_replace_profile_block "${USER_HOME}/.zshrc"
else
  info "${USER_HOME}/.zshrc not found; creating and adding Go environment block."
  add_or_replace_profile_block "${USER_HOME}/.zshrc"
fi

# Ensure GOPATH directory exists and owned by user
GOPATH_DIR="${USER_HOME}/go"
if [[ ! -d "$GOPATH_DIR" ]]; then
  info "Creating GOPATH dir $GOPATH_DIR"
  mkdir -p "$GOPATH_DIR"
fi
chown -R "$TARGET_USER":"$TARGET_USER" "$GOPATH_DIR"

info "Go environment configured. Note: user must re-open their shell or run 'source ~/.bashrc' or 'source ~/.zshrc' to pick changes."
}

########################
# 8) Allow user to use sudo without password
########################
no_pass() {
info "Passwordless sudo is a sensitive change."
if confirm "Enable passwordless sudo for ${TARGET_USER}? (y/N)"; then
  SUDOERS_FILE="/etc/sudoers.d/${TARGET_USER}-nopasswd"
  info "Creating sudoers drop-in at $SUDOERS_FILE"
  printf "%s ALL=(ALL) NOPASSWD:ALL\n" "$TARGET_USER" > "$SUDOERS_FILE"
  chmod 0440 "$SUDOERS_FILE"
  info "Validating sudoers syntax with visudo -cf ..."
  if visudo -cf "$SUDOERS_FILE"; then
    info "Sudoers file syntax OK. Passwordless sudo enabled for $TARGET_USER."
  else
    rm -f "$SUDOERS_FILE"
    fail "Sudoers validation failed; file removed. No changes made to sudoers."
  fi
else
  info "Skipping passwordless sudo configuration."
fi
}

########################
# Setup Background
########################
set_xfce4_background() {
    local target_user=${SUDO_USER:-$USER}
    local user_home
    user_home=$(eval echo "~$target_user")

    local props
    props=$(sudo -u "$target_user" xfconf-query -c xfce4-desktop -l | grep last-image)
    
    if [[ -z "$props" ]]; then
        fail "No xfce4-desktop background properties found."
        return 1
    fi

    # Update property
    sudo -u "$target_user" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u $target_user)/bus" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitorVirtual1/workspace0/last-image -s /usr/share/backgrounds/kali-16x9/kali-oleo.png -t string --create

    sudo -u "$target_user" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u $target_user)/bus" xfconf-query -c xfce4-session -p /splash/engines/simple/Image -s /usr/share/backgrounds/kali-16x9/kali-oleo.png -t string --create

    if [[ $? -eq 0 ]]; then
        info "Background image successfully set"
    else
        fail "Failed to set background image."
        return 1
    fi
}

########################
# Main 
########################
update_upgrade
setup_xfce4_terminal
setup_zsh_with_datetime_prompt
setup_tmux
be_owner
install_go
configure_rc_files
no_pass
set_xfce4_background

read -n1 -r -p "Press any key to reboot the system..." key
echo
sudo reboot
