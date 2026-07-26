#!/usr/bin/env bash
# ============================================================================
# Sway/SwayFX Setup Script
# https://github.com/JevonThompsonx/sway
# ============================================================================
# Interactive setup for Sway/SwayFX window manager with Waybar, Foot, Alacritty
# Supports: Fedora, Rocky Linux / RHEL, Ubuntu / Debian
# ============================================================================

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ─────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
ask()     { echo -e "${CYAN}[?]${NC} $*"; }

confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-y}"
    if [[ "$default" == "y" ]]; then
        read -rp "$(echo -e "${CYAN}[?]${NC} ${prompt} [Y/n] ")" answer
        answer="${answer:-y}"
    else
        read -rp "$(echo -e "${CYAN}[?]${NC} ${prompt} [y/N] ")" answer
        answer="${answer:-n}"
    fi
    [[ "$answer" =~ ^[Yy] ]]
}

# ── OS Detection ────────────────────────────────────────────────────────────
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
        OS_NAME="$PRETTY_NAME"
    else
        error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi

    case "$OS_ID" in
        fedora)     PKG_MANAGER="dnf" ;;
        rocky|rhel|centos) PKG_MANAGER="dnf" ;;
        ubuntu|debian|pop) PKG_MANAGER="apt" ;;
        arch|manjaro) PKG_MANAGER="pacman" ;;
        *)
            warn "Unknown OS: $OS_ID. Will attempt dnf."
            PKG_MANAGER="dnf"
            ;;
    esac
    info "Detected: ${OS_NAME} (${PKG_MANAGER})"
}

# ── GPU Detection ───────────────────────────────────────────────────────────
detect_gpu() {
    GPU_INFO=""
    HAS_NVIDIA=false
    HAS_INTEL=false
    HAS_AMD=false
    INTEL_CARD=""
    NVIDIA_CARD=""

    if command -v lspci &>/dev/null; then
        GPU_INFO=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)
    fi

    if echo "$GPU_INFO" | grep -qi nvidia; then
        HAS_NVIDIA=true
        info "NVIDIA GPU detected"
    fi
    if echo "$GPU_INFO" | grep -qi intel; then
        HAS_INTEL=true
        info "Intel GPU detected"
    fi
    if echo "$GPU_INFO" | grep -qiE 'amd|radeon'; then
        HAS_AMD=true
        info "AMD GPU detected"
    fi

    # Detect which /dev/dri/card is which GPU
    # card0 and card1 are assigned by kernel — check vendor ID to map correctly
    if [[ -d /dev/dri ]]; then
        for card_path in /sys/class/drm/card[0-9]*; do
            [[ -f "$card_path/device/vendor" ]] || continue
            local vendor
            vendor=$(cat "$card_path/device/vendor")
            local card_name
            card_name=$(basename "$card_path")
            case "$vendor" in
                0x8086) INTEL_CARD="/dev/dri/$card_name" ;;
                0x10de) NVIDIA_CARD="/dev/dri/$card_name" ;;
            esac
        done
        [[ -n "$INTEL_CARD" ]] && info "Intel GPU: $INTEL_CARD"
        [[ -n "$NVIDIA_CARD" ]] && info "NVIDIA GPU: $NVIDIA_CARD"
    fi
}

# ── Display Detection ───────────────────────────────────────────────────────
detect_display() {
    # Find connected output from the Intel GPU (usually eDP-1 for laptops)
    OUTPUT_NAME="eDP-1"
    if command -v swaymsg &>/dev/null && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        OUTPUT_NAME=$(swaymsg -t get_outputs 2>/dev/null | jq -r '.[0].name' 2>/dev/null || echo "eDP-1")
    else
        # Try to detect from sysfs
        for card_path in /sys/class/drm/card[0-9]*; do
            for output in "$card_path"/card*-*; do
                if [[ -f "$output/status" ]] && [[ "$(cat "$output/status")" == "connected" ]]; then
                    OUTPUT_NAME=$(basename "$output" | sed 's/^[^-]*-//')
                    break 2
                fi
            done
        done
    fi
    info "Display output: ${OUTPUT_NAME}"
}

# ── Sway vs SwayFX ──────────────────────────────────────────────────────────
choose_compositor() {
    echo ""
    echo -e "${BOLD}Choose your compositor:${NC}"
    echo "  1) Sway    - Standard Wayland compositor (i3-compatible)"
    echo "  2) SwayFX  - Sway with eye candy (blur, rounded corners, shadows)"
    echo ""
    read -rp "$(echo -e "${CYAN}[?]${NC} Select [1-2] (default: 2): ")" choice
    choice="${choice:-2}"

    if [[ "$choice" == "2" ]]; then
        USE_SWAYFX=true
        info "Using SwayFX"
    else
        USE_SWAYFX=false
        info "Using standard Sway"
    fi
}

# ── Rocky/RHEL COPR Setup ───────────────────────────────────────────────────
setup_rocky_copr() {
    info "Enabling COPR repos for Rocky/RHEL..."

    # Enable CRB repo (needed for meson, ninja-build, etc.)
    sudo dnf config-manager --set-enabled crb 2>/dev/null || true

    # Sway ecosystem packages (sway, foot, mako, swaybg, swayidle, swaylock, wmenu)
    sudo dnf copr enable -y @sway-sig/epel 2>/dev/null || warn "Failed to enable @sway-sig/epel"

    # Extra tools (grim, slurp, gtk-layer-shell)
    sudo dnf copr enable -y alonid/hyprland rhel+epel-10-x86_64 2>/dev/null || warn "Failed to enable alonid/hyprland"

    success "COPR repos enabled"
}

# ── Rocky/RHEL Package Installation ─────────────────────────────────────────
install_packages_rocky() {
    # Enable COPR repos first
    setup_rocky_copr

    # Packages available in repos + COPR
    local packages=(
        # Core (from @sway-sig/epel COPR)
        sway foot mako swaybg swayidle swaylock wmenu
        # Screenshots (from alonid/hyprland COPR)
        grim slurp
        # Fonts
        fira-code-fonts
        # Misc (from base repos)
        jq curl wget git
        # Wayland portals (file dialogs, screenshots, secrets)
        xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr
        # Keyring (Bitwarden, app passwords — auto-unlocks via PAM on login)
        gnome-keyring
        # Seat management
        seatd
    )

    info "Installing packages via dnf..."
    sudo dnf install -y "${packages[@]}" 2>&1 | tail -5

    # Install lsd for fish ls function
    sudo dnf install -y lsd 2>/dev/null || warn "lsd not available"

    # Install network-manager-applet (nm-applet)
    sudo dnf install -y network-manager-applet 2>/dev/null || warn "network-manager-applet not available"

    # Enable seatd
    sudo systemctl enable --now seatd 2>/dev/null || warn "Failed to enable seatd"

    # Build waybar from source (not in repos)
    if ! command -v waybar &>/dev/null; then
        build_waybar
    fi

    # Handle SwayFX vs Sway choice
    if [[ "$USE_SWAYFX" == true ]]; then
        warn "SwayFX on Rocky/RHEL requires building wlroots 0.20 + scenefx from source."
        warn "This is complex and may conflict with system wlroots."
        if confirm "Use vanilla Sway instead? (recommended for Rocky)" "y"; then
            USE_SWAYFX=false
            info "Using vanilla Sway (already installed)"
        else
            warn "SwayFX must be built manually. See README.md for instructions."
            USE_SWAYFX=false
        fi
    fi
}

# ── Build Waybar from Source ────────────────────────────────────────────────
build_waybar() {
    info "Building waybar from source..."

    # Install build dependencies
    sudo dnf install -y meson ninja-build cmake gcc-c++ \
        wayland-devel wayland-protocols-devel libdrm-devel libxkbcommon-devel \
        pcre2-devel json-c-devel pango-devel cairo-devel pixman-devel \
        libinput-devel libseat-devel hwdata gtk3-devel gtk-layer-shell-devel \
        scdoc librsvg2-devel vulkan-loader-devel libdisplay-info-devel \
        gtkmm3.0-devel 2>&1 | tail -5

    cd /tmp
    rm -rf Waybar
    git clone https://github.com/Alexays/Waybar.git 2>&1 | tail -3
    cd Waybar

    # Use system PATH to avoid linuxbrew conflicts
    PATH="/usr/bin:/usr/local/bin:/bin:/usr/sbin:/sbin" \
        meson setup build -Dman-pages=disabled -Dtests=disabled 2>&1 | tail -5

    PATH="/usr/bin:/usr/local/bin:/bin:/usr/sbin:/sbin" \
        ninja -C build 2>&1 | tail -5

    sudo PATH="/usr/bin:/usr/local/bin:/bin:/usr/sbin:/sbin" \
        ninja -C build install 2>&1 | tail -5

    cd -
    rm -rf /tmp/Waybar

    success "Waybar built and installed"
}

# ── Fedora Package Installation ─────────────────────────────────────────────
install_packages_fedora() {
    local packages=(
        # Core
        sway foot alacritty
        # Audio
        pipewire-utils pipewire-pulse pavucontrol
        # Bluetooth
        blueman
        # Notifications
        mako
        # Clipboard
        wl-clipboard
        # Screenshots
        grim slurp
        # Hardware
        brightnessctl playerctl
        # Network
        network-manager-applet
        # File manager
        thunar
        # Fonts
        fira-code-fonts
        # Misc
        jq curl wget git
        # Wayland portals (file dialogs, screenshots, secrets)
        xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr
        # Keyring (Bitwarden, app passwords — auto-unlocks via PAM on login)
        gnome-keyring
    )

    # SwayFX on Fedora
    if [[ "$USE_SWAYFX" == true ]]; then
        info "Enabling SwayFX COPR repo..."
        sudo dnf copr enable -y mochaa/swayfx 2>/dev/null || \
            warn "COPR enable failed - SwayFX may need manual install"
        packages=(swayfx "${packages[@]/sway/}")
    fi

    info "Installing packages via dnf..."
    sudo dnf install -y "${packages[@]}" 2>&1 | tail -5
}

# ── Ubuntu/Debian Package Installation ──────────────────────────────────────
install_packages_apt() {
    local packages=(
        sway foot alacritty
        pipewire-utils pipewire-pulse
        blueman mako-notifier
        wl-clipboard grim slurp
        brightnessctl playerctl
        network-manager-gnome
        thunar
        fonts-firacode
        jq curl wget git
        # Wayland portals (file dialogs, screenshots, secrets)
        xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr
        # Keyring (Bitwarden, app passwords — auto-unlocks via PAM on login)
        gnome-keyring
    )

    if [[ "$USE_SWAYFX" == true ]]; then
        warn "SwayFX not in Ubuntu repos. Building from source requires meson + dependencies."
        if confirm "Install standard Sway instead?" "y"; then
            USE_SWAYFX=false
        else
            error "SwayFX must be built from source on Ubuntu. See: https://github.com/WillPower3309/swayfx"
            USE_SWAYFX=false
        fi
    fi

    info "Installing packages via apt..."
    sudo apt update -qq
    sudo apt install -y "${packages[@]}" 2>&1 | tail -5
}

# ── Package Installation Router ─────────────────────────────────────────────
install_packages() {
    case "$PKG_MANAGER" in
        dnf)
            if [[ "$OS_ID" == "rocky" || "$OS_ID" == "rhel" || "$OS_ID" == "centos" ]]; then
                install_packages_rocky
            else
                install_packages_fedora
            fi
            ;;
        apt)  install_packages_apt ;;
        *)
            error "Unsupported package manager: $PKG_MANAGER"
            exit 1
            ;;
    esac
}

# ── Optional Packages ───────────────────────────────────────────────────────
install_optional() {
    echo ""
    echo -e "${BOLD}Optional packages:${NC}"
    echo "  These aren't required but referenced in the default config."
    echo ""

    declare -A optional_pkgs=(
        ["copyq"]="Clipboard manager GUI"
        ["nwg-drawer"]="App drawer (GNOME-style)"
        ["nwg-bar"]="Shutdown/logout menu"
        ["wpaperd"]="Wallpaper daemon (cargo)"
        ["dunst"]="Notification daemon (alternative to mako)"
    )

    for pkg in "${!optional_pkgs[@]}"; do
        local desc="${optional_pkgs[$pkg]}"
        if command -v "$pkg" &>/dev/null; then
            success "$pkg already installed"
        else
            if confirm "Install $pkg? ($desc)" "n"; then
                case "$pkg" in
                    wpaperd)
                        if command -v cargo &>/dev/null; then
                            cargo install wpaperd
                            cargo install wpaperctl
                        else
                            warn "cargo not found. Install Rust first: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
                        fi
                        ;;
                    *)
                        sudo "$PKG_MANAGER" install -y "$pkg" 2>/dev/null || \
                            warn "Failed to install $pkg - may not be in repos"
                        ;;
                esac
            fi
        fi
    done
}

# ── Nerd Fonts ──────────────────────────────────────────────────────────────
install_nerd_fonts() {
    echo ""
    info "Checking Nerd Fonts..."

    local font_name="FiraCode Nerd Font"
    if fc-list 2>/dev/null | grep -qi "$font_name"; then
        success "$font_name already installed"
        return
    fi

    if confirm "Install FiraCode Nerd Font? (required for terminal configs)" "y"; then
        local nerd_version="3.4.0"
        local font_dir="$HOME/.local/share/fonts/firacode-nerd"
        mkdir -p "$font_dir"

        info "Downloading FiraCode Nerd Font v${nerd_version}..."
        curl -sL "https://github.com/ryanoasis/nerd-fonts/releases/download/v${nerd_version}/FiraCode.zip" \
            -o /tmp/FiraCode-Nerd.zip

        info "Extracting..."
        unzip -o /tmp/FiraCode-Nerd.zip -d "$font_dir/" &>/dev/null
        rm /tmp/FiraCode-Nerd.zip

        info "Refreshing font cache..."
        fc-cache -fv "$font_dir/" &>/dev/null

        if fc-list | grep -qi "$font_name"; then
            success "$font_name installed"
        else
            error "Font installation may have failed. Check fc-list."
        fi
    fi
}

# ── Config Deployment ───────────────────────────────────────────────────────
deploy_configs() {
    echo ""
    info "Deploying configs..."

    local config_dir="$HOME/.config"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Sway config
    if confirm "Deploy sway config?" "y"; then
        mkdir -p "$config_dir/sway/config.d"

        # Back up existing config
        if [[ -f "$config_dir/sway/config" ]]; then
            local backup="$config_dir/sway/config.bak.$(date +%s)"
            cp "$config_dir/sway/config" "$backup"
            info "Backed up existing config to $backup"
        fi

        # Deploy the config from this repo
        if [[ -f "$script_dir/sway-config" ]]; then
            cp "$script_dir/sway-config" "$config_dir/sway/config"

            # Auto-detect and fix display settings
            if [[ "$OUTPUT_NAME" != "eDP-1" ]]; then
                sed -i "s/output eDP-1/output $OUTPUT_NAME/" "$config_dir/sway/config"
                info "Updated output to $OUTPUT_NAME"
            fi

            # Fix browser if needed
            if [[ -f "$config_dir/sway/config" ]]; then
                if ! command -v firefox &>/dev/null && command -v falkon &>/dev/null; then
                    sed -i 's/set \$browser firefox/set \$browser falkon/' "$config_dir/sway/config"
                    info "Set browser to falkon (firefox not found)"
                fi
            fi

            success "Sway config deployed"
        else
            error "sway-config file not found in repo"
        fi
    fi

    # Waybar config
    if confirm "Deploy waybar config?" "y"; then
        mkdir -p "$config_dir/waybar"

        if [[ -f "$script_dir/waybar-config.jsonc" ]]; then
            cp "$script_dir/waybar-config.jsonc" "$config_dir/waybar/config.jsonc"
            cp "$script_dir/waybar-style.css" "$config_dir/waybar/style.css"
            success "Waybar config deployed"
        elif [[ -f "$HOME/waybar-configs-sway/config.jsonc" ]]; then
            cp "$HOME/waybar-configs-sway/config.jsonc" "$config_dir/waybar/"
            cp "$HOME/waybar-configs-sway/style.css" "$config_dir/waybar/"
            success "Waybar config deployed from local clone"
        else
            info "Cloning waybar-configs-sway..."
            git clone https://github.com/JevonThompsonx/waybar-configs-sway.git /tmp/waybar-configs-sway-setup 2>/dev/null
            if [[ -d /tmp/waybar-configs-sway-setup ]]; then
                cp /tmp/waybar-configs-sway-setup/config.jsonc "$config_dir/waybar/"
                cp /tmp/waybar-configs-sway-setup/style.css "$config_dir/waybar/"
                rm -rf /tmp/waybar-configs-sway-setup
                success "Waybar config deployed"
            else
                warn "Failed to clone waybar repo"
            fi
        fi
    fi

    # Foot config
    if confirm "Deploy foot config?" "y"; then
        mkdir -p "$config_dir/foot"
        if [[ -f "$script_dir/foot.ini" ]]; then
            cp "$script_dir/foot.ini" "$config_dir/foot/foot.ini"
            success "Foot config deployed"
        fi
    fi

    # Alacritty theme (needed for the config)
    if [[ ! -d "$config_dir/alacritty/themes" ]]; then
        if confirm "Clone alacritty themes? (needed for flat_remix theme)" "y"; then
            git clone https://github.com/alacritty/alacritty-theme.git \
                "$config_dir/alacritty/themes" 2>/dev/null || warn "Failed to clone themes"
        fi
    fi

    # Environment file for Wayland
    deploy_environment_file

    # Portals config (file dialogs, screenshots, secrets)
    deploy_portals_conf

    # Fish helper functions
    if command -v fish &>/dev/null; then
        if confirm "Deploy fish helper functions? (ls, n)" "y"; then
            mkdir -p "$config_dir/fish/functions"
            [[ -f "$script_dir/fish-ls.fish" ]] && cp "$script_dir/fish-ls.fish" "$config_dir/fish/functions/ls.fish"
            [[ -f "$script_dir/fish-n.fish" ]] && cp "$script_dir/fish-n.fish" "$config_dir/fish/functions/n.fish"
            success "Fish functions deployed"
        fi
    fi

    # Screenshots directory
    mkdir -p "$HOME/Pictures/Screenshots"

    # wpaperd wallpaper daemon
    if command -v wpaperd &>/dev/null; then
        if confirm "Deploy wpaperd config? (rotates wallpapers from ~/Pictures/WPs)" "y"; then
            mkdir -p "$config_dir/wpaperd"
            cat > "$config_dir/wpaperd/config.toml" << 'EOF'
[default]
path = "/home/jevonx/Pictures/WPs"
duration = "30m"
sorting = "random"
EOF
            success "wpaperd config deployed"
        fi
    fi

    # Clone WPs wallpaper repo
    if [[ ! -d "$HOME/Pictures/WPs" ]]; then
        if confirm "Clone WPs wallpaper repo? (needed for wpaperd)" "y"; then
            git clone https://github.com/JevonThompsonx/WPs.git "$HOME/Pictures/WPs" 2>/dev/null || warn "Failed to clone WPs repo"
        fi
    fi
}

# ── Environment File ────────────────────────────────────────────────────────
deploy_environment_file() {
    local env_file="$HOME/.config/sway/environment"

    # Back up existing
    if [[ -f "$env_file" ]]; then
        cp "$env_file" "$env_file.bak.$(date +%s)"
    fi

    # Build the environment file with correct GPU card
    cat > "$env_file" << EOF
# User-specific environment variables for Sway
# These are read by sway BEFORE initialization — critical for GPU selection

# ── GPU Selection ────────────────────────────────────────────────────────
# WLR_DRM_DEVICES must be set BEFORE sway starts (not via exec in config)
# Intel GPU is preferred for stability on Wayland with NVIDIA Optimus
EOF

    if [[ -n "$INTEL_CARD" ]]; then
        echo "WLR_DRM_DEVICES=$INTEL_CARD" >> "$env_file"
        info "Set WLR_DRM_DEVICES=$INTEL_CARD (Intel GPU)"
    fi

    cat >> "$env_file" << 'EOF'

# ── Wayland compatibility ────────────────────────────────────────────────
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
QT_QPA_PLATFORMTHEME=qt6ct

# ── XDG session ──────────────────────────────────────────────────────────
XDG_CURRENT_DESKTOP=sway
XDG_SESSION_DESKTOP=sway
EOF

    success "Environment file deployed to $env_file"
}

# ── Portals Config ───────────────────────────────────────────────────────
deploy_portals_conf() {
    local portals_dir="$HOME/.config/xdg-desktop-portal"
    local portals_file="$portals_dir/portals.conf"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    mkdir -p "$portals_dir"

    if [[ -f "$script_dir/portals.conf" ]]; then
        cp "$script_dir/portals.conf" "$portals_file"
        success "Portals config deployed to $portals_file"
    else
        # Generate inline if file not found
        cat > "$portals_file" << 'EOF'
[preferred]
default=gtk
org.freedesktop.impl.portal.ScreenCast=wlr
org.freedesktop.impl.portal.Screenshot=wlr
org.freedesktop.impl.portal.Secret=gnome-keyring
org.freedesktop.impl.portal.Inhibit=none
EOF
        success "Portals config generated at $portals_file"
    fi
}

# ── NVIDIA Setup ────────────────────────────────────────────────────────────
setup_nvidia() {
    if [[ "$HAS_NVIDIA" != true ]]; then
        return
    fi

    echo ""
    warn "NVIDIA GPU detected. Sway needs special config for NVIDIA Optimus."
    echo ""
    echo "  Options:"
    echo "    1) Use Intel GPU only (recommended for stability)"
    echo "    2) Use NVIDIA proprietary with env vars (experimental)"
    echo ""
    read -rp "$(echo -e "${CYAN}[?]${NC} Select [1-2] (default: 1): ")" nv_choice
    nv_choice="${nv_choice:-1}"

    local env_file="$HOME/.config/sway/environment"
    case "$nv_choice" in
        1)
            info "Configuring for Intel-only GPU..."
            if [[ -n "$INTEL_CARD" ]]; then
                # Update or add WLR_DRM_DEVICES in environment file
                if grep -q "WLR_DRM_DEVICES" "$env_file" 2>/dev/null; then
                    sed -i "s|WLR_DRM_DEVICES=.*|WLR_DRM_DEVICES=$INTEL_CARD|" "$env_file"
                else
                    echo "WLR_DRM_DEVICES=$INTEL_CARD" >> "$env_file"
                fi
                success "Intel GPU configured: $INTEL_CARD"
            else
                warn "Could not detect Intel GPU card path. Set WLR_DRM_DEVICES manually in $env_file"
            fi
            ;;
        2)
            info "Adding NVIDIA proprietary env vars..."
            cat >> "$env_file" << 'EOF'

# ── NVIDIA Proprietary ──────────────────────────────────────────────────
WLR_NO_HARDWARE_CURSORS=1
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
EOF
            # Update WLR_DRM_DEVICES to use NVIDIA card
            if [[ -n "$NVIDIA_CARD" ]]; then
                if grep -q "WLR_DRM_DEVICES" "$env_file" 2>/dev/null; then
                    sed -i "s|WLR_DRM_DEVICES=.*|WLR_DRM_DEVICES=$NVIDIA_CARD|" "$env_file"
                else
                    echo "WLR_DRM_DEVICES=$NVIDIA_CARD" >> "$env_file"
                fi
            fi
            success "NVIDIA env vars added to $env_file"
            ;;
    esac
}

# ── GDM Session Setup ───────────────────────────────────────────────────────
setup_gdm_session() {
    echo ""
    info "Setting up GDM session entry..."

    # Create wrapper script for GDM
    local wrapper="/usr/local/bin/sway-launch.sh"
    sudo tee "$wrapper" > /dev/null << 'WRAPPER'
#!/bin/bash
# Sway launcher wrapper for GDM
# Ensures environment variables are set before sway starts

# Source user environment file if it exists
if [[ -f "$HOME/.config/sway/environment" ]]; then
    set -a
    source "$HOME/.config/sway/environment"
    set +a
fi

# GNOME Keyring — PAM module sets GNOME_KEYRING_CONTROL but Sway may lose it
# Derive from XDG_RUNTIME_DIR which PAM always sets
if [ -z "$GNOME_KEYRING_CONTROL" ] && [ -d "$XDG_RUNTIME_DIR/keyring" ]; then
    export GNOME_KEYRING_CONTROL="$XDG_RUNTIME_DIR/keyring"
fi

# Ensure user paths are available
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:$PATH"

# Launch sway
exec sway "$@"
WRAPPER
    sudo chmod +x "$wrapper"
    success "Wrapper script: $wrapper"

    # Create/update desktop entry
    local desktop="/usr/share/wayland-sessions/sway.desktop"
    sudo tee "$desktop" > /dev/null << 'DESKTOP'
[Desktop Entry]
Name=Sway
Comment=An i3-compatible Wayland compositor
Exec=/usr/local/bin/sway-launch.sh
Type=Application
DesktopNames=sway
DESKTOP
    success "GDM session entry: $desktop"
}

# ── Enable Services ─────────────────────────────────────────────────────────
enable_services() {
    echo ""
    info "Checking services..."

    # Bluetooth
    if systemctl is-enabled bluetooth &>/dev/null; then
        success "Bluetooth service enabled"
    else
        if confirm "Enable Bluetooth service?" "y"; then
            sudo systemctl enable --now bluetooth 2>/dev/null || warn "Failed to enable bluetooth"
        fi
    fi

    # NetworkManager
    if systemctl is-enabled NetworkManager &>/dev/null; then
        success "NetworkManager enabled"
    else
        if confirm "Enable NetworkManager?" "y"; then
            sudo systemctl enable --now NetworkManager 2>/dev/null || warn "Failed to enable NetworkManager"
        fi
    fi

    # seatd (needed for wlroots on Rocky/RHEL)
    if systemctl is-enabled seatd &>/dev/null; then
        success "seatd service enabled"
    else
        if confirm "Enable seatd service? (recommended for wlroots)" "y"; then
            sudo systemctl enable --now seatd 2>/dev/null || warn "Failed to enable seatd"
        fi
    fi
}

# ── Fish Shell Setup ────────────────────────────────────────────────────────
setup_fish() {
    if ! command -v fish &>/dev/null; then
        return
    fi

    echo ""
    if confirm "Set fish as default shell?" "n"; then
        local fish_path
        fish_path=$(command -v fish)
        if ! grep -q "$fish_path" /etc/shells; then
            echo "$fish_path" | sudo tee -a /etc/shells &>/dev/null
        fi
        chsh -s "$fish_path"
        success "Default shell set to fish"
    fi
}

# ── Summary ─────────────────────────────────────────────────────────────────
print_summary() {
    local sway_cmd="sway"
    [[ "$USE_SWAYFX" == true ]] && sway_cmd="swayfx"

    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}Setup Complete!${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Compositor:  ${CYAN}${sway_cmd}${NC}"
    echo -e "  Config:      ${CYAN}~/.config/sway/config${NC}"
    echo -e "  Environment: ${CYAN}~/.config/sway/environment${NC}"
    echo -e "  Waybar:      ${CYAN}~/.config/waybar/${NC}"
    echo -e "  Terminal:    ${CYAN}alacritty${NC} (backup: foot)"
    echo -e "  Launcher:    ${CYAN}wmenu${NC}"
    echo -e "  Browser:     ${CYAN}falkon${NC}"
    echo -e "  Fonts:       ${CYAN}FiraCode Nerd Font${NC}"
    echo ""
    echo -e "  ${BOLD}To start:${NC}"
    echo -e "    Log out and select ${CYAN}Sway${NC} from GDM login screen"
    echo ""
    echo -e "  ${BOLD}Key bindings:${NC}"
    echo -e "    Super+T        Terminal (alacritty)"
    echo -e "    Super+Shift+T  Backup terminal (foot)"
    echo -e "    Super+D        App launcher (wmenu)"
    echo -e "    Super+B        Browser (falkon)"
    echo -e "    Super+Q        Close window"
    echo -e "    Super+F        Fullscreen"
    echo -e "    Super+S        Screenshot selection"
    echo -e "    Super+Shift+S  Screenshot full"
    echo -e "    Super+Escape   Lock screen"
    echo -e "    Super+1-0      Switch workspace"
    echo ""
    echo -e "  ${BOLD}Repos:${NC}"
    echo -e "    https://github.com/JevonThompsonx/sway"
    echo -e "    https://github.com/JevonThompsonx/waybar-configs-sway"
    echo ""
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Sway / SwayFX Setup${NC}"
    echo -e "${BOLD}  github.com/JevonThompsonx/sway${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # Pre-flight checks
    if [[ $EUID -eq 0 ]]; then
        error "Don't run this as root. It will use sudo when needed."
        exit 1
    fi

    detect_os
    detect_gpu
    detect_display
    choose_compositor

    echo ""
    echo -e "${BOLD}This script will:${NC}"
    echo "  - Install sway, waybar, foot, alacritty, wmenu, and dependencies"
    echo "  - Install FiraCode Nerd Font"
    echo "  - Deploy sway, waybar, and foot configs"
    echo "  - Set up GDM session entry"
    [[ "$HAS_NVIDIA" == true ]] && echo "  - Configure NVIDIA GPU settings"
    echo ""

    if ! confirm "Proceed with installation?" "y"; then
        echo "Aborted."
        exit 0
    fi

    install_packages
    install_optional
    install_nerd_fonts
    deploy_configs
    setup_nvidia
    setup_gdm_session
    enable_services
    setup_fish
    print_summary
}

main "$@"
