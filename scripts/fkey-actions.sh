#!/bin/sh
# F-key action handler for HP ZBook 15 G3 on Sway

notify() {
    notify-send -u normal -t 2000 -i "$1" "$2" "$3" 2>/dev/null
}

BACKLIGHT="/sys/class/backlight/intel_backlight/brightness"
MAX_BRIGHTNESS="/sys/class/backlight/intel_backlight/max_brightness"

case "$1" in
    1)
        # Swaylock with random wallpaper from ~/Pictures/WPs + Fira Code Nerd Font + clock
        wp=$(find ~/Pictures/WPs -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.webp" \) 2>/dev/null | shuf -n1)
        notify system-lock-screen "Lock Screen" "Locking..."
        swaylock -i "$wp" \
            --font "FiraCode Nerd Font" \
            --indicator-radius 100 --indicator-thickness 8 \
            --ring-color 282c34 --ring-ver-color 61afef --ring-wrong-color e06c75 --ring-clear-color e5c07b \
            --key-hl-color 61afef --bs-hl-color e06c75 \
            --inside-color 282c34 --inside-ver-color 282c34 --inside-wrong-color 282c34 --inside-clear-color 282c34 \
            --line-color 00000000 --separator-color 00000000 \
            --text-color abb2bf --text-ver-color abb2bf --text-wrong-color e06c75 --text-clear-color e5c07b \
            --clock --datestr "%Y-%m-%d" --timestr "%H:%M" --fade-in 0.2
        ;;
    2)
        # Rename — forward F2 keypress to focused window
        if command -v wtype >/dev/null 2>&1; then
            wtype -k F2
            notify edit-rename "Rename" "F2 sent to focused window"
        else
            notify edit-rename "Rename" "wtype not installed (sudo dnf install wtype)"
        fi
        ;;
    3)
        # Keyboard backlight toggle
        kbd_led="/sys/class/leds/input3::scrolllock/brightness"
        if [ -f "$kbd_led" ]; then
            cur=$(cat "$kbd_led" 2>/dev/null)
            if [ "$cur" != "0" ]; then
                echo 0 | sudo tee "$kbd_led" > /dev/null 2>&1
                notify input-keyboard "Keyboard Backlight" "OFF"
            else
                echo 1 | sudo tee "$kbd_led" > /dev/null 2>&1
                notify input-keyboard "Keyboard Backlight" "ON"
            fi
        else
            notify dialog-information "Keyboard Backlight" "No backlight device found"
        fi
        ;;
    4)
        # Display toggle — show active outputs
        active=$(swaymsg -t get_outputs 2>/dev/null | python3 -c "import json,sys; [print(o['name']) for o in json.load(sys.stdin) if o.get('active')]" 2>/dev/null)
        notify preferences-desktop-display "Displays" "Active: ${active:-none}"
        ;;
    5)
        # Brightness down
        current=$(cat "$BACKLIGHT" 2>/dev/null)
        max=$(cat "$MAX_BRIGHTNESS" 2>/dev/null)
        step=$((max / 20))
        new=$((current - step))
        [ "$new" -lt 0 ] && new=0
        echo "$new" | sudo tee "$BACKLIGHT" > /dev/null 2>&1
        pct=$((new * 100 / max))
        notify display-brightness "Brightness" "▼ ${pct}%"
        ;;
    6)
        # Brightness up
        current=$(cat "$BACKLIGHT" 2>/dev/null)
        max=$(cat "$MAX_BRIGHTNESS" 2>/dev/null)
        step=$((max / 20))
        new=$((current + step))
        [ "$new" -gt "$max" ] && new="$max"
        echo "$new" | sudo tee "$BACKLIGHT" > /dev/null 2>&1
        pct=$((new * 100 / max))
        notify display-brightness "Brightness" "▲ ${pct}%"
        ;;
    7)
        # Media play/pause via dbus
        if dbus-send --print-reply --dest=org.mpris.MediaPlayer2.playerctld /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.PlayPause 2>/dev/null | grep -q "method return"; then
            notify media-playback-start "Media" "Play/Pause toggled"
        else
            notify dialog-information "Media" "No media player active"
        fi
        ;;
    8)
        # Volume down (sink)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 2>/dev/null
        wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- 2>/dev/null
        vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print int($2*100)}')
        notify audio-volume-low "Volume" "▼ ${vol}%"
        ;;
    9)
        # Volume up (sink)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 2>/dev/null
        wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ 2>/dev/null
        vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print int($2*100)}')
        notify audio-volume-high "Volume" "▲ ${vol}%"
        ;;
    10)
        # Mic mute toggle (source only — never touches sink volume)
        cur=$(wpctl get-mute @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | awk '{print $2}')
        if [ "$cur" = "[MUTED]" ]; then
            wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0 2>/dev/null
            notify microphone-sensitivity-high "Microphone" "Unmuted"
        else
            wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1 2>/dev/null
            notify microphone-sensitivity-muted "Microphone" "Muted"
        fi
        ;;
    11)
        # Eject disc
        eject 2>/dev/null && notify media-optical "Eject" "Tray opened" || notify dialog-information "Eject" "No disc drive"
        ;;
    12)
        # Wifi toggle
        state=$(nmcli radio wifi 2>/dev/null)
        if [ "$state" = "enabled" ]; then
            nmcli radio wifi off 2>/dev/null
            notify network-wireless-offline "Wi-Fi" "OFF"
        else
            nmcli radio wifi on 2>/dev/null
            notify network-wireless "Wi-Fi" "ON"
        fi
        ;;
esac
