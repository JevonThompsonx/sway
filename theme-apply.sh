#!/usr/bin/env bash
# ============================================================================
# Dracula Dark Theme Setup — JevonThompsonx dotfiles
# https://github.com/JevonThompsonx/sway
# ============================================================================
# Installs Dracula GTK theme + Papirus-Dark icon theme and applies dark mode
# globally. Safe to re-run. Idempotent.
#
# Supports: Fedora, Rocky Linux / RHEL, Ubuntu / Debian
# Tested on: Rocky Linux 10.2
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

DRACULA_VERSION="v4.0.0"
DRACULA_URL="https://github.com/dracula/gtk/releases/download/${DRACULA_VERSION}/Dracula.tar.xz"
THEMES_DIR="${HOME}/.themes"
ICONS_DIR="${HOME}/.local/share/icons"
GTK3_INI="${HOME}/.config/gtk-3.0/settings.ini"
GTK4_INI="${HOME}/.config/gtk-4.0/settings.ini"

# ── OS Detection ────────────────────────────────────────────────────────────
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="$ID"
    case "$OS_ID" in
        fedora|rocky|rhel|centos) PKG="dnf" ;;
        ubuntu|debian|pop)        PKG="apt" ;;
        arch|manjaro)             PKG="pacman" ;;
        *)
            warn "Unknown OS: $OS_ID. Package install will be skipped."
            PKG=""
            ;;
    esac
else
    err "/etc/os-release not found. Cannot detect OS."
    exit 1
fi
info "Detected: ${PRETTY_NAME:-${OS_ID}} (${PKG})"

# ── Install Dracula GTK Theme ───────────────────────────────────────────────
install_dracula() {
    if [[ -d "${THEMES_DIR}/Dracula" ]] && [[ -f "${THEMES_DIR}/Dracula/gtk-3.0/gtk.css" ]]; then
        ok "Dracula GTK theme already installed at ${THEMES_DIR}/Dracula"
        return
    fi

    info "Downloading Dracula GTK theme ${DRACULA_VERSION}..."
    mkdir -p "${THEMES_DIR}"
    local tmp
    tmp=$(mktemp -d)
    if ! curl -fsSL "${DRACULA_URL}" -o "${tmp}/Dracula.tar.xz"; then
        err "Failed to download Dracula from ${DRACULA_URL}"
        rm -rf "${tmp}"
        return 1
    fi

    info "Extracting..."
    tar -xJf "${tmp}/Dracula.tar.xz" -C "${THEMES_DIR}/"
    rm -rf "${tmp}"

    if [[ -d "${THEMES_DIR}/Dracula" ]]; then
        ok "Dracula GTK theme installed"
    else
        err "Dracula extraction failed"
        return 1
    fi
}

# ── Install Papirus-Dark Icon Theme ─────────────────────────────────────────
install_papirus() {
    if [[ -d "/usr/share/icons/Papirus-Dark" ]] || [[ -d "${ICONS_DIR}/Papirus-Dark" ]]; then
        ok "Papirus-Dark already installed"
        return
    fi

    [[ -z "$PKG" ]] && { warn "Skipping Papirus-Dark install (unknown package manager)"; return; }

    info "Installing Papirus-Dark via $PKG..."
    case "$PKG" in
        dnf)
            sudo dnf install -y papirus-icon-theme-dark 2>&1 | tail -3
            ;;
        apt)
            sudo apt update -qq
            sudo apt install -y papirus-icon-theme 2>&1 | tail -3
            ;;
        pacman)
            sudo pacman -S --noconfirm papirus-icon-theme 2>&1 | tail -3
            ;;
    esac
    ok "Papirus-Dark installed"
}

# ── Apply via gsettings ─────────────────────────────────────────────────────
apply_gsettings() {
    if ! command -v gsettings &>/dev/null; then
        warn "gsettings not found, skipping live GSettings apply"
        return
    fi

    info "Applying dark theme via gsettings..."
    gsettings set org.gnome.desktop.interface color-scheme    'prefer-dark'
    gsettings set org.gnome.desktop.interface gtk-theme       'Dracula'
    gsettings set org.gnome.desktop.interface icon-theme      'Papirus-Dark'
    ok "gsettings applied: gtk-theme=Dracula, icon-theme=Papirus-Dark, color-scheme=prefer-dark"
}

# ── Write settings.ini for explicit persistence ─────────────────────────────
write_settings_ini() {
    info "Writing GTK 3/4 settings.ini files for persistence..."
    mkdir -p "$(dirname "${GTK3_INI}")" "$(dirname "${GTK4_INI}")"

    cat > "${GTK3_INI}" << 'EOF'
[Settings]
gtk-theme-name=Dracula
gtk-application-prefer-dark-theme=1
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Adwaita
gtk-font-name=Red Hat Text Regular 11
EOF

    cat > "${GTK4_INI}" << 'EOF'
[Settings]
gtk-theme-name=Dracula
gtk-application-prefer-dark-theme=1
gtk-icon-theme-name=Papirus-Dark
EOF

    ok "Wrote ${GTK3_INI}"
    ok "Wrote ${GTK4_INI}"
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  Dracula Dark Theme Setup"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    install_dracula
    install_papirus
    apply_gsettings
    write_settings_ini

    echo ""
    ok "Dark theme applied. Reload apps to see effect."
    echo "     • logout/login for full GTK 3/4 app refresh"
    echo "     • or run: gsettings set org.gnome.desktop.interface gtk-theme Dracula"
    echo ""
}

main "$@"
