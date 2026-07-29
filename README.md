# Sway Setup Guide for Aphrodite

**Target machine:** HP ZBook 15 G3 (Intel i7-6820HQ, Intel HD 530 + NVIDIA Quadro M2000M, 31GB RAM)
**OS:** Rocky Linux 10.2 (Red Quartz)
**Source machine:** MacBook Pro 2015 (Kentucky) — configs from [JevonThompsonx/sway](https://github.com/JevonThompsonx/sway)

---

## Overview

Aphrodite runs Rocky Linux 10.2, which does **not** have Sway or most ecosystem tools in its official repos. Everything must be installed from COPR repos or built from source.

### What's Already Working

| Component | Status | Notes |
|-----------|--------|-------|
| Wayland session | ✅ Active | GNOME on Wayland |
| Alacritty | ✅ 0.17.0 | Catppuccin Mocha, JetBrainsMono Nerd Font |
| Fish shell | ✅ 4.2.0 | zoxide, atuin configured |
| wlroots | ✅ 0.18.2 | In EPEL (used by Sway) |
| NVIDIA driver | ✅ 580.173.02 | Quadro M2000M, modeset=1 |

### What Gets Installed

| Component | Version | Method | Notes |
|-----------|---------|--------|-------|
| Sway | 1.10.1 | `@sway-sig/epel` COPR | i3-compatible Wayland compositor |
| Waybar | 0.15.0 | Built from source | Status bar |
| Foot | 1.20.2 | `@sway-sig/epel` COPR | Backup terminal |
| Mako | 1.10.0 | `@sway-sig/epel` COPR | Notification daemon |
| Swaybg | 1.2.1 | `@sway-sig/epel` COPR | Wallpaper |
| Swayidle | 1.8.0 | `@sway-sig/epel` COPR | Idle management |
| Swaylock | 1.8.0 | `@sway-sig/epel` COPR | Screen lock |
| Wmenu | 0.1.9 | `@sway-sig/epel` COPR | App launcher |
| Grim + Slurp | 1.5.0 | `alonid/hyprland` COPR | Screenshots |
| XDG Desktop Portal | — | System | Portal service (file dialogs) |
| XDG Portal GTK | — | System | GTK file chooser backend |
| XDG Portal WLR | — | System | wlroots screen capture |
| GNOME Keyring | 42.1 | System | Secret storage (auto-unlock via PAM) |
| Wl-clipboard | — | Already installed | Clipboard |
| Lsd | 1.2.0 | EPEL | `ls` replacement for fish |
| Seatd | 0.9.3 | EPEL | Seat management for wlroots |
| FiraCode Nerd Font | 3.4.0 | Downloaded | Terminal font |

### GPU Card Mapping (IMPORTANT)

The kernel assigns card numbers at boot — they are NOT fixed. Always check:

```bash
# Check which card is which GPU
cat /sys/class/drm/card*/device/vendor
# 0x8086 = Intel, 0x10de = NVIDIA

# Check connected outputs
cat /sys/class/drm/card*/card*-*​/status
```

On Aphrodite:
- **card0** = NVIDIA Quadro M2000M (0x10de) — DP-4, DP-5, DP-6 (all disconnected)
- **card1** = Intel HD 530 (0x8086) — **eDP-1 (connected)**, HDMI-A-1/2/3 (disconnected)

**The Intel GPU drives the laptop display.** Sway must use card1 for eDP-1.

---

## Quick Install

```bash
# Clone the repo
git clone https://github.com/JevonThompsonx/sway.git ~/sway-setup
cd ~/sway-setup

# Run the interactive setup script
chmod +x setup.sh
./setup.sh
```

The script will:
1. Detect your OS, GPU, and display
2. Enable required COPR repos (Rocky/RHEL)
3. Install all packages
4. Build waybar from source if needed
5. Deploy configs with correct GPU card mapping
6. Set up GDM session entry
7. Install FiraCode Nerd Font

---

## Manual Install

### Step 1: Enable COPR Repos (Rocky/RHEL only)

```bash
sudo dnf config-manager --set-enabled crb
sudo dnf copr enable -y @sway-sig/epel
sudo dnf copr enable -y alonid/hyprland rhel+epel-10-x86_64
```

### Step 2: Install Packages

```bash
sudo dnf install -y \
    sway foot mako swaybg swayidle swaylock wmenu \
    grim slurp fira-code-fonts jq curl wget git \
    xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr \
    gnome-keyring seatd lsd network-manager-applet
```

### Step 3: Build Waybar from Source

```bash
# Install build deps
sudo dnf install -y meson ninja-build cmake gcc-c++ \
    wayland-devel wayland-protocols-devel libdrm-devel libxkbcommon-devel \
    pcre2-devel json-c-devel pango-devel cairo-devel pixman-devel \
    libinput-devel libseat-devel hwdata gtk3-devel gtk-layer-shell-devel \
    scdoc librsvg2-devel vulkan-loader-devel libdisplay-info-devel \
    gtkmm3.0-devel

# Build
cd /tmp && git clone https://github.com/Alexays/Waybar.git && cd Waybar
PATH="/usr/bin:/usr/local/bin:/bin:/usr/sbin:/sbin" meson setup build -Dman-pages=disabled -Dtests=disabled
PATH="/usr/bin:/usr/local/bin:/bin:/usr/sbin:/sbin" ninja -C build
sudo ninja -C build install
```

### Step 4: Deploy Configs

```bash
# Copy configs
mkdir -p ~/.config/sway ~/.config/waybar ~/.config/foot ~/.config/xdg-desktop-portal
cp ~/sway-setup/sway-config ~/.config/sway/config
cp ~/sway-setup/sway-environment ~/.config/sway/environment
cp ~/sway-setup/portals.conf ~/.config/xdg-desktop-portal/portals.conf
cp ~/sway-setup/waybar-config.jsonc ~/.config/waybar/config.jsonc
cp ~/sway-setup/waybar-style.css ~/.config/waybar/style.css
cp ~/sway-setup/foot.ini ~/.config/foot/foot.ini

# Install font
mkdir -p ~/.local/share/fonts/firacode-nerd
curl -sL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.zip" -o /tmp/FiraCode.zip
unzip /tmp/FiraCode.zip -d ~/.local/share/fonts/firacode-nerd/
fc-cache -fv
```

### Step 5: Set Up GDM Session

```bash
# Create wrapper script
sudo tee /usr/local/bin/sway-launch.sh << 'EOF'
#!/bin/bash
if [[ -f "$HOME/.config/sway/environment" ]]; then
    set -a
    source "$HOME/.config/sway/environment"
    set +a
fi
# GNOME Keyring — PAM sets GNOME_KEYRING_CONTROL but Sway may lose it
if [ -z "$GNOME_KEYRING_CONTROL" ] && [ -d "$XDG_RUNTIME_DIR/keyring" ]; then
    export GNOME_KEYRING_CONTROL="$XDG_RUNTIME_DIR/keyring"
fi
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:$PATH"
exec sway "$@"
EOF
sudo chmod +x /usr/local/bin/sway-launch.sh

# Create desktop entry
sudo tee /usr/share/wayland-sessions/sway.desktop << 'EOF'
[Desktop Entry]
Name=Sway
Comment=An i3-compatible Wayland compositor
Exec=/usr/local/bin/sway-launch.sh
Type=Application
DesktopNames=sway
EOF
```

### Step 6: Enable Services

```bash
sudo systemctl enable --now seatd
```

---

## Config Files

| File | Purpose |
|------|---------|
| `sway-config` | Main sway config (keybindings, appearance, startup) |
| `sway-environment` | Env vars read BEFORE sway starts (GPU selection, Wayland compat) |
| `portals.conf` | XDG portal routing (file dialogs, screenshots, secrets) |
| `waybar-config.jsonc` | Waybar modules and layout |
| `waybar-style.css` | Waybar styling |
| `foot.ini` | Foot terminal config |
| `alacritty.toml` | Alacritty terminal config |
| `fish-ls.fish` | Fish function: `ls` → `lsd` |
| `fish-n.fish` | Fish function: `n` → `fastfetch` |

---

## Key Bindings

| Key | Action |
|-----|--------|
| `Super+T` | Terminal (alacritty) |
| `Super+Shift+T` | Backup terminal (foot) |
| `Super+D` | App launcher (wmenu) |
| `Super+B` | Browser (falkon) |
| `Super+Q` | Close window |
| `Super+F` | Fullscreen |
| `Super+S` | Screenshot selection |
| `Super+Shift+S` | Full screenshot |
| `Super+Escape` | Lock screen (swaylock) |
| `Super+Shift+R` | Reload config |
| `Super+1-0` | Switch workspace |
| `Super+Shift+1-0` | Move window to workspace |

---

## Troubleshooting

### Sway won't start from GDM

1. Check the wrapper script exists and is executable:
   ```bash
   ls -la /usr/local/bin/sway-launch.sh
   ```

2. Check the environment file has the correct GPU card:
   ```bash
   cat ~/.config/sway/environment | grep WLR_DRM_DEVICES
   ```

3. Verify which card is Intel:
   ```bash
   cat /sys/class/drm/card*/device/vendor
   # 0x8086 = Intel, 0x10de = NVIDIA
   ```

4. Check sway logs:
   ```bash
   journalctl --user -b | grep -i sway
   ```

### No display output

```bash
# List available outputs
ls /dev/dri/
# Check connected outputs
cat /sys/class/drm/card*/card*-*​/status
```

### NVIDIA issues

If Intel-only mode doesn't work, try NVIDIA:
```bash
# Edit environment file
vim ~/.config/sway/environment
# Change: WLR_DRM_DEVICES=/dev/dri/card0
# Add: WLR_NO_HARDWARE_CURSORS=1
```

### Waybar not showing

```bash
# Run manually to see errors
waybar 2>&1 | tee /tmp/waybar.log
```

### File dialogs not working (bookmark import/export, Bitwarden export)

File dialogs in browsers and apps need `xdg-desktop-portal` to work under Wayland.
Symptoms: clicking "Import/Export" does nothing, no file picker appears.

```bash
# Check portal services are running
systemctl --user status xdg-desktop-portal.service
systemctl --user status xdg-desktop-portal-gtk.service

# If portal-gtk is crashed with "cannot open display:", env not propagated
# Fix: reload sway config (Ctrl+Shift+R) or restart portals
systemctl --user restart xdg-desktop-portal.service
systemctl --user restart xdg-desktop-portal-gtk.service

# Verify portals.conf exists
cat ~/.config/xdg-desktop-portal/portals.conf

# Check portal logs for errors
journalctl --user -u xdg-desktop-portal-gtk.service -n 20
```

The sway config must propagate env to systemd for portals to find the Wayland display:
```bash
# This line in ~/.config/sway/config startup section is critical:
exec dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_RUNTIME_DIR GNOME_KEYRING_CONTROL SSH_AUTH_SOCK
```

### Bitwarden asks for password on every reboot

Bitwarden uses `gnome-keyring` for secret storage. The keyring is unlocked at login
by PAM, but Sway may lose the `GNOME_KEYRING_CONTROL` env var.

```bash
# Check if keyring control socket exists
ls $XDG_RUNTIME_DIR/keyring/control

# Check if env var is set
echo $GNOME_KEYRING_CONTROL

# If empty, the wrapper script needs the keyring fix (see setup.sh)
# Quick fix: export it manually
export GNOME_KEYRING_CONTROL="$XDG_RUNTIME_DIR/keyring"

# Verify keyring is accessible
secret-tool store --label="test" service test-key  # should prompt once
secret-tool lookup service test-key                  # should return password
secret-tool clear service test-key                   # cleanup
```

---

## Kentucky vs Aphrodite

| | Kentucky (MacBook) | Aphrodite (ZBook) |
|---|---|---|
| OS | Fedora 44 | Rocky Linux 10.2 |
| CPU | Intel i5-5257U (2c/4t) | Intel i7-6820HQ (4c/8t) |
| GPU | Intel Iris 6100 | Intel HD 530 + NVIDIA M2000M |
| RAM | 16GB | 31GB |
| Display | 2560x1600 @ 2x | 1920x1080 @ 1x |
| Sway | Sway (from repos) | Sway 1.10.1 (COPR) |
| Terminal | Alacritty + Foot | Alacritty (primary) + Foot (backup) |
| Shell | Fish 4.6.0 | Fish 4.2.0 |
| Package Mgr | dnf | dnf (Rocky) |

---

## Config Adjustments Made

When deploying Kentucky's config to Aphrodite:

1. **GPU card mapping** — Intel=card1 (not card0). Set via `WLR_DRM_DEVICES` in environment file.
2. **Display output** — `eDP-1` confirmed connected on card1.
3. **Browser** — `firefox` → `falkon` (firefox not installed).
4. **Launcher** — `wofi` → `wmenu` (wofi not available on Rocky).
5. **Environment file** — GPU vars moved from `exec export` in config to environment file (must be set BEFORE sway starts).
6. **GDM session** — Wrapper script created to source environment file before launching sway.
7. **Seatd** — Installed and enabled (required for wlroots on Rocky).
8. **Removed SwayFX directives** — blur, shadows, corner_radius (vanilla sway doesn't support these).

---

## Dark Theme (Dracula GTK + Papirus-Dark)

The system uses a unified dark theme stack:

| Layer | Theme |
|-------|-------|
| Wayland window borders | `#282c34` (One Dark) |
| Status bar (waybar) | Catppuccin Mocha |
| Terminal (alacritty) | Catppuccin Mocha inline |
| Terminal (foot) | Black + ANSI palette |
| Launcher (wofi) | `#292e42` background |
| GTK apps (gsettings) | **Dracula** |
| Icon theme | **Papirus-Dark** |
| Color scheme | `prefer-dark` |

### Apply dark theme on a new system

Run `theme-apply.sh` directly:

```bash
./theme-apply.sh
```

This will:
1. Download Dracula GTK theme from GitHub releases (v4.0.0) → `~/.themes/Dracula`
2. Install Papirus-Dark icon theme via `dnf` / `apt` / `pacman`
3. Set gsettings: `gtk-theme=Dracula`, `icon-theme=Papirus-Dark`, `color-scheme=prefer-dark`
4. Write `~/.config/gtk-3.0/settings.ini` and `~/.config/gtk-4.0/settings.ini` for persistence

Safe to re-run (idempotent).

### Auto-applied by

- `setup.sh` — fresh install (prompts)
- `deploy.sh` — one-shot deploy (prompts)
