#!/usr/bin/env bash
# ============================================================================
# Aphrodite Sway Deploy Script
# HP ZBook 15 G3 — Rocky Linux 10.2 — Intel HD 530 + NVIDIA Quadro M2000M
# ============================================================================
# Run this script on Aphrodite to deploy all sway-related configs.
# Assumes build tools and packages are already installed (see README.md).
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config"

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Aphrodite Sway Deploy${NC}"
echo -e "${BOLD}  HP ZBook 15 G3 — Rocky Linux 10.2${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""

# ── Detect GPU Card Mapping ─────────────────────────────────────────────────
info "Detecting GPU card mapping..."
INTEL_CARD=""
NVIDIA_CARD=""
for card_path in /sys/class/drm/card[0-9]*; do
    [[ -f "$card_path/device/vendor" ]] || continue
    vendor=$(cat "$card_path/device/vendor")
    card_name=$(basename "$card_path")
    case "$vendor" in
        0x8086) INTEL_CARD="/dev/dri/$card_name" ;;
        0x10de) NVIDIA_CARD="/dev/dri/$card_name" ;;
    esac
done
[[ -n "$INTEL_CARD" ]] && info "Intel GPU: $INTEL_CARD"
[[ -n "$NVIDIA_CARD" ]] && info "NVIDIA GPU: $NVIDIA_CARD"

# ── Detect Display ──────────────────────────────────────────────────────────
info "Detecting display..."
OUTPUT_NAME="eDP-1"
if command -v swaymsg &>/dev/null && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    OUTPUT_NAME=$(swaymsg -t get_outputs 2>/dev/null | jq -r '.[0].name' 2>/dev/null || echo "eDP-1")
else
    for card_path in /sys/class/drm/card[0-9]*; do
        for output in "$card_path"/card*-*; do
            if [[ -f "$output/status" ]] && [[ "$(cat "$output/status")" == "connected" ]]; then
                OUTPUT_NAME=$(basename "$output" | sed 's/^[^-]*-//')
                break 2
            fi
        done
    done
fi
info "Display output: $OUTPUT_NAME"

# ── Backup ──────────────────────────────────────────────────────────────────
BACKUP_DIR="$CONFIG_DIR/backups/aphrodite-deploy-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

for dir in sway waybar foot alacritty; do
    if [[ -d "$CONFIG_DIR/$dir" ]]; then
        cp -r "$CONFIG_DIR/$dir" "$BACKUP_DIR/"
        info "Backed up $dir"
    fi
done
success "Backups at $BACKUP_DIR"

# ── Sway Config ─────────────────────────────────────────────────────────────
if confirm "Deploy sway config?" "y"; then
    mkdir -p "$CONFIG_DIR/sway/config.d"

    if [[ -f "$SCRIPT_DIR/sway-config" ]]; then
        cp "$SCRIPT_DIR/sway-config" "$CONFIG_DIR/sway/config"
    else
        error "sway-config not found in $SCRIPT_DIR"
        exit 1
    fi

    # Fix display output name
    if [[ "$OUTPUT_NAME" != "eDP-1" ]]; then
        sed -i "s/output eDP-1/output $OUTPUT_NAME/" "$CONFIG_DIR/sway/config"
        info "Updated output to $OUTPUT_NAME"
    fi

    # Fix browser
    if ! command -v firefox &>/dev/null && command -v falkon &>/dev/null; then
        sed -i 's/set \$browser firefox/set \$browser falkon/' "$CONFIG_DIR/sway/config"
        info "Set browser to falkon"
    fi

    success "Sway config deployed"
fi

# ── Environment File ────────────────────────────────────────────────────────
if confirm "Deploy sway environment file?" "y"; then
    ENV_FILE="$CONFIG_DIR/sway/environment"
    mkdir -p "$CONFIG_DIR/sway"

    cat > "$ENV_FILE" << EOF
# User-specific environment variables for Sway
# These are read by sway BEFORE initialization — critical for GPU selection

# ── GPU Selection ────────────────────────────────────────────────────────
# WLR_DRM_DEVICES must be set BEFORE sway starts (not via exec in config)
# Intel GPU is preferred for stability on Wayland with NVIDIA Optimus
EOF

    if [[ -n "$INTEL_CARD" ]]; then
        echo "WLR_DRM_DEVICES=$INTEL_CARD" >> "$ENV_FILE"
        info "Set WLR_DRM_DEVICES=$INTEL_CARD (Intel GPU)"
    fi

    cat >> "$ENV_FILE" << 'EOF'

# ── Wayland compatibility ────────────────────────────────────────────────
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
QT_QPA_PLATFORMTHEME=qt6ct

# ── XDG session ──────────────────────────────────────────────────────────
XDG_CURRENT_DESKTOP=sway
XDG_SESSION_DESKTOP=sway
EOF

    success "Environment file deployed"
fi

# ── Portals Config ───────────────────────────────────────────────────────
if confirm "Deploy portals config? (required for file dialogs)" "y"; then
    PORTALS_DIR="$CONFIG_DIR/xdg-desktop-portal"
    mkdir -p "$PORTALS_DIR"

    if [[ -f "$SCRIPT_DIR/portals.conf" ]]; then
        cp "$SCRIPT_DIR/portals.conf" "$PORTALS_DIR/portals.conf"
    else
        cat > "$PORTALS_DIR/portals.conf" << 'EOF'
[preferred]
default=gtk
org.freedesktop.impl.portal.ScreenCast=wlr
org.freedesktop.impl.portal.Screenshot=wlr
org.freedesktop.impl.portal.Secret=gnome-keyring
org.freedesktop.impl.portal.Inhibit=none
EOF
    fi
    success "Portals config deployed"
fi

# ── Waybar Config ───────────────────────────────────────────────────────────
if confirm "Deploy waybar config?" "y"; then
    mkdir -p "$CONFIG_DIR/waybar"

    if [[ -f "$SCRIPT_DIR/waybar-config.jsonc" ]]; then
        cp "$SCRIPT_DIR/waybar-config.jsonc" "$CONFIG_DIR/waybar/config.jsonc"
        cp "$SCRIPT_DIR/waybar-style.css" "$CONFIG_DIR/waybar/style.css"
        success "Waybar config deployed"
    elif [[ -f "$HOME/waybar-configs-sway/config.jsonc" ]]; then
        cp "$HOME/waybar-configs-sway/config.jsonc" "$CONFIG_DIR/waybar/"
        cp "$HOME/waybar-configs-sway/style.css" "$CONFIG_DIR/waybar/"
        success "Waybar config deployed from local clone"
    else
        warn "Waybar config not found"
    fi
fi

# ── Sway Scripts (power-menu, network, bluetooth, fkey-actions) ──────────
if [[ -d "$SCRIPT_DIR/scripts" ]]; then
    if confirm "Deploy sway scripts? (power-menu, network, bluetooth, fkey-actions)" "y"; then
        mkdir -p "$CONFIG_DIR/sway/scripts"
        for script in "$SCRIPT_DIR/scripts/"*.sh; do
            [[ -f "$script" ]] || continue
            cp "$script" "$CONFIG_DIR/sway/scripts/"
            chmod +x "$CONFIG_DIR/sway/scripts/$(basename "$script")"
        done
        success "Sway scripts deployed to $CONFIG_DIR/sway/scripts/"

        # If fkey-actions.sh is deployed, also install to /usr/local/bin for $mod+F-key binds
        if [[ -f "$CONFIG_DIR/sway/scripts/fkey-actions.sh" ]] && confirm "Install fkey-actions.sh to /usr/local/bin? (needed for F1-F12 bindsyms)" "n"; then
            sudo cp "$CONFIG_DIR/sway/scripts/fkey-actions.sh" /usr/local/bin/fkey-actions.sh
            sudo chmod +x /usr/local/bin/fkey-actions.sh
            success "fkey-actions.sh installed to /usr/local/bin/"
        fi
    fi
fi

# ── Foot Config ─────────────────────────────────────────────────────────────
if confirm "Deploy foot config?" "y"; then
    mkdir -p "$CONFIG_DIR/foot"
    if [[ -f "$SCRIPT_DIR/foot.ini" ]]; then
        cp "$SCRIPT_DIR/foot.ini" "$CONFIG_DIR/foot/foot.ini"
        success "Foot config deployed"
    fi
fi

# ── Alacritty ───────────────────────────────────────────────────────────────
if confirm "Deploy alacritty config? (will overwrite existing)" "n"; then
    mkdir -p "$CONFIG_DIR/alacritty"
    if [[ -f "$SCRIPT_DIR/alacritty.toml" ]]; then
        cp "$SCRIPT_DIR/alacritty.toml" "$CONFIG_DIR/alacritty/alacritty.toml"
    fi

    # Clone themes if needed
    if [[ ! -d "$CONFIG_DIR/alacritty/themes" ]]; then
        info "Cloning alacritty themes..."
        git clone https://github.com/alacritty/alacritty-theme.git \
            "$CONFIG_DIR/alacritty/themes" 2>/dev/null || warn "Failed to clone themes"
    fi
    success "Alacritty config deployed"
else
    info "Skipped alacritty (keeping existing config)"
fi

# ── Dark Theme (Dracula GTK + Papirus-Dark icons) ──────────────────────────
if [[ -f "$SCRIPT_DIR/theme-apply.sh" ]]; then
    if confirm "Apply Dracula dark theme? (Dracula GTK + Papirus-Dark icons)" "y"; then
        bash "$SCRIPT_DIR/theme-apply.sh" || warn "theme-apply.sh failed — dark theme not applied"
    fi
fi

# ── Fish Functions ──────────────────────────────────────────────────────────
if confirm "Deploy fish helper functions? (ls, n)" "y"; then
    mkdir -p "$CONFIG_DIR/fish/functions"
    [[ -f "$SCRIPT_DIR/fish-ls.fish" ]] && cp "$SCRIPT_DIR/fish-ls.fish" "$CONFIG_DIR/fish/functions/ls.fish"
    [[ -f "$SCRIPT_DIR/fish-n.fish" ]] && cp "$SCRIPT_DIR/fish-n.fish" "$CONFIG_DIR/fish/functions/n.fish"
    success "Fish functions deployed"
fi

# ── Nerd Fonts ──────────────────────────────────────────────────────────────
if ! fc-list 2>/dev/null | grep -qi "FiraCode Nerd Font"; then
    if confirm "Install FiraCode Nerd Font?" "y"; then
        FONT_DIR="$HOME/.local/share/fonts/firacode-nerd"
        mkdir -p "$FONT_DIR"
        info "Downloading FiraCode Nerd Font..."
        curl -sL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.zip" \
            -o /tmp/FiraCode-Nerd.zip
        unzip -o /tmp/FiraCode-Nerd.zip -d "$FONT_DIR/" &>/dev/null
        rm /tmp/FiraCode-Nerd.zip
        fc-cache -fv "$FONT_DIR/" &>/dev/null
        success "FiraCode Nerd Font installed"
    fi
else
    success "FiraCode Nerd Font already installed"
fi

# ── GDM Session Entry ──────────────────────────────────────────────────────
if confirm "Set up GDM session entry?" "y"; then
    # Create wrapper script
    WRAPPER="/usr/local/bin/sway-launch.sh"
    sudo tee "$WRAPPER" > /dev/null << 'WRAPPER'
#!/bin/bash
# Sway launcher wrapper for GDM
# Source user environment file if it exists
if [[ -f "$HOME/.config/sway/environment" ]]; then
    set -a
    source "$HOME/.config/sway/environment"
    set +a
fi
# GNOME Keyring — PAM module sets GNOME_KEYRING_CONTROL but Sway may lose it
if [ -z "$GNOME_KEYRING_CONTROL" ] && [ -d "$XDG_RUNTIME_DIR/keyring" ]; then
    export GNOME_KEYRING_CONTROL="$XDG_RUNTIME_DIR/keyring"
fi
# Ensure user paths are available
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:$PATH"
# Launch sway
exec sway "$@"
WRAPPER
    sudo chmod +x "$WRAPPER"
    success "Wrapper script: $WRAPPER"

    # Create desktop entry
    DESKTOP="/usr/share/wayland-sessions/sway.desktop"
    sudo tee "$DESKTOP" > /dev/null << 'DESKTOP'
[Desktop Entry]
Name=Sway
Comment=An i3-compatible Wayland compositor
Exec=/usr/local/bin/sway-launch.sh
Type=Application
DesktopNames=sway
DESKTOP
    success "GDM session entry: $DESKTOP"
fi

# ── Screenshots dir ─────────────────────────────────────────────────────────
mkdir -p "$HOME/Pictures/Screenshots"

# ── WPs Wallpaper Repo ─────────────────────────────────────────────────────
if [[ ! -d "$HOME/Pictures/WPs" ]]; then
    if confirm "Clone WPs wallpaper repo?" "y"; then
        git clone https://github.com/JevonThompsonx/WPs.git "$HOME/Pictures/WPs" 2>/dev/null || warn "Failed to clone WPs repo"
    fi
fi

# ── wpaperd Config ──────────────────────────────────────────────────────────
if command -v wpaperd &>/dev/null; then
    if confirm "Deploy wpaperd config? (rotates wallpapers from ~/Pictures/WPs every 30m)" "y"; then
        mkdir -p "$CONFIG_DIR/wpaperd"
        cat > "$CONFIG_DIR/wpaperd/config.toml" << 'EOF'
[default]
path = "/home/jevonx/Pictures/WPs"
duration = "30m"
sorting = "random"
EOF
        success "wpaperd config deployed"
    fi
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}Deploy Complete!${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Configs:     ${CYAN}~/.config/sway/${NC}"
echo -e "  Waybar:      ${CYAN}~/.config/waybar/${NC}"
echo -e "  Foot:        ${CYAN}~/.config/foot/${NC}"
echo -e "  Backups:     ${CYAN}$BACKUP_DIR${NC}"
echo ""
echo -e "  ${BOLD}To start Sway:${NC}"
echo -e "    Log out and select ${CYAN}Sway${NC} from GDM login screen"
echo ""
echo -e "  ${BOLD}Key bindings:${NC}"
echo -e "    Super+T        Terminal (alacritty)"
echo -e "    Super+Shift+T  Backup terminal (foot)"
echo -e "    Super+D        App launcher (rofi)"
echo -e "    Super+B        Browser (falkon)"
echo -e "    Super+Q        Close window"
echo -e "    Super+S        Screenshot"
echo -e "    Super+Escape   Lock screen"
echo ""
