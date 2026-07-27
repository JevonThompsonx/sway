#!/bin/bash
# Power menu script for rofi

CHOSEN=$(echo -e "⏻  Shutdown\n  Reboot\n  Lock\n  Logout" | rofi -dmenu -i -p "Power" -theme-str 'window {width: 300px;}')

case "$CHOSEN" in
    *Shutdown*)
        systemctl poweroff
        ;;
    *Reboot*)
        systemctl reboot
        ;;
    *Lock*)
        swaylock -c 000000
        ;;
    *Logout*)
        swaymsg exit
        ;;
esac
