#!/bin/bash

# ==========================================
#  Universal Terminal Setup Script by iElibazz
#  Supports: Debian, Ubuntu, Mint, Proxmox (LXC/Host), Arch, Fedora, Alpine, Termux
# ==========================================

set -e

# --- VARIABLES ---
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/UbuntuMono.zip"
# Updated to new dotfiles repo (Raw Link)
STARSHIP_CONFIG_URL="https://raw.githubusercontent.com/iElibazz/dotfiles/main/starship.toml"

# Colors for pretty output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERR]${NC} $1"; }
log_guide() { echo -e "${CYAN}$1${NC}"; }

# --- 1. DETECT ENVIRONMENT ---
log_info "Detecting Environment..."

# Detect User Privileges
if [ "$EUID" -eq 0 ]; then
    SUDO_CMD=""
    log_warn "Running as ROOT. Sudo will not be used."
else
    if command -v sudo &> /dev/null; then
        SUDO_CMD="sudo"
    else
        log_err "Not root and 'sudo' not found. Cannot install packages. Exiting."
        exit 1
    fi
fi

# Detect Distro & Package Manager
if [ -n "$TERMUX_VERSION" ]; then
    DISTRO="termux"
    PKG_MGR="pkg install -y"
    PKG_UPDATE="pkg update -y"
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    case $DISTRO in
        debian|ubuntu|linuxmint|pop|kali)
            PKG_MGR="$SUDO_CMD apt-get install -y"
            PKG_UPDATE="$SUDO_CMD apt-get update -y"
            ;;
        arch|manjaro)
            PKG_MGR="$SUDO_CMD pacman -S --noconfirm"
            PKG_UPDATE="$SUDO_CMD pacman -Sy"
            ;;
        fedora|centos|rhel)
            PKG_MGR="$SUDO_CMD dnf install -y"
            PKG_UPDATE="$SUDO_CMD dnf check-update"
            ;;
        alpine)
            PKG_MGR="$SUDO_CMD apk add"
            PKG_UPDATE="$SUDO_CMD apk update"
            ;;
        *)
            log_warn "Unknown distro '$DISTRO'. Attempting to continue, but package installation might fail."
            PKG_MGR=""
            ;;
    esac
fi

log_info "Detected: $DISTRO"

# Detect Shell
CURRENT_SHELL=$(basename "$SHELL")
if [ "$CURRENT_SHELL" = "zsh" ]; then
    RC_FILE="$HOME/.zshrc"
elif [ "$CURRENT_SHELL" = "fish" ]; then
    RC_FILE="$HOME/.config/fish/config.fish"
else
    RC_FILE="$HOME/.bashrc"
fi
log_info "Targeting Shell Config: $RC_FILE"


# --- 2. INSTALL PACKAGES ---
log_info "Installing Dependencies..."
if [ -n "$PKG_MGR" ]; then
    $PKG_UPDATE || true # Continue even if update has minor errors
    
    # Package list varies slightly by distro
    case $DISTRO in
        alpine)
            $PKG_MGR wget unzip fontconfig curl git
            ;;
        *)
            $PKG_MGR wget unzip fontconfig curl git
            ;;
    esac
fi


# --- 3. INSTALL FONT ---
log_info "Installing Ubuntu Mono Nerd Font..."

if [ "$DISTRO" = "termux" ]; then
    mkdir -p ~/.termux
    wget -qO /tmp/UbuntuMono.zip "$FONT_URL"
    # Specific extraction for Termux
    unzip -o /tmp/UbuntuMono.zip "UbuntuMonoNerdFontMono-Regular.ttf" -d /tmp/
    mv /tmp/UbuntuMonoNerdFontMono-Regular.ttf ~/.termux/font.ttf
    termux-reload-settings
else
    FONT_DIR="$HOME/.local/share/fonts"
    mkdir -p "$FONT_DIR"
    wget -qO /tmp/UbuntuMono.zip "$FONT_URL"
    # Extract only the Mono Regular version to avoid bloat
    unzip -o /tmp/UbuntuMono.zip "UbuntuMonoNerdFontMono-Regular.ttf" -d "$FONT_DIR"
    if command -v fc-cache &> /dev/null; then
        fc-cache -fv
    fi
fi
rm -f /tmp/UbuntuMono.zip


# --- 4. INSTALL STARSHIP ---
log_info "Installing Starship..."
if ! command -v starship &> /dev/null; then
    sh -c "$(curl -fsSL https://starship.rs/install.sh)" -- -y
else
    log_info "Starship already installed."
fi

# Configure Starship
mkdir -p ~/.config
STARSHIP_FILE="$HOME/.config/starship.toml"

if [ -f "$STARSHIP_FILE" ]; then
    log_warn "Existing Starship config found. Backing up..."
    mv "$STARSHIP_FILE" "$STARSHIP_FILE.bak.$TIMESTAMP"
fi

log_info "Downloading Custom Starship Config..."
wget -qO "$STARSHIP_FILE" "$STARSHIP_CONFIG_URL"

# Enable in Shell
if ! grep -q "starship init $CURRENT_SHELL" "$RC_FILE"; then
    echo "" >> "$RC_FILE"
    echo "# Starship Prompt" >> "$RC_FILE"
    echo 'eval "$(starship init '$CURRENT_SHELL')"' >> "$RC_FILE"
fi


# --- 5. INSTALL EZA ---
log_info "Installing eza..."
if ! command -v eza &> /dev/null; then
    # Eza installation is tricky across distros, handled case-by-case
    case $DISTRO in
        termux|alpine|arch|manjaro|fedora)
            $PKG_MGR eza
            ;;
        debian|ubuntu|linuxmint|kali|pop)
            # Official Eza Repo setup for Debian/Ubuntu
            $SUDO_CMD mkdir -p /etc/apt/keyrings
            wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | $SUDO_CMD gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
            echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | $SUDO_CMD tee /etc/apt/sources.list.d/gierens.list
            $SUDO_CMD chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
            $PKG_UPDATE
            $PKG_MGR eza
            ;;
        *)
            log_warn "Could not automatically install eza for $DISTRO. Skipping."
            ;;
    esac
else
    log_info "Eza already installed."
fi


# --- 6. CONFIGURE ALIASES ---
log_info "Configuring Aliases..."

# Check if alias already exists
if ! grep -q "alias ls='eza'" "$RC_FILE"; then
    echo "" >> "$RC_FILE"
    echo "# Eza Aliases" >> "$RC_FILE"
    # Option A: 'ls' is now 'eza'
    echo "alias ls='eza'" >> "$RC_FILE"
fi

# --- 7. POST-INSTALL GUIDANCE ---
echo ""
log_info "--------------------------------------------------------"
log_info "INSTALLATION COMPLETE"
log_info "--------------------------------------------------------"
echo ""
log_guide "⚠️  IMPORTANT: ICON DISPLAY ISSUES"
echo "If you see boxes or question marks [?] instead of icons, read this:"
echo ""
echo "1. IF YOU ARE ON DESKTOP (GNOME/KDE):"
echo "   Open your Terminal Preferences and set the font to 'UbuntuMono Nerd Font'."
echo ""
echo "2. IF YOU ARE CONNECTING VIA SSH (PROXMOX/REMOTE SERVER):"
echo "   The font must be installed on YOUR CLIENT COMPUTER (the one you are typing on),"
echo "   not just the server. Configure PuTTY, VSCode, or Terminal.app to use"
echo "   'UbuntuMono Nerd Font' locally."
echo ""
log_info "Restarting shell to apply changes..."
sleep 3

# Restart Shell
exec "$CURRENT_SHELL"
