#!/bin/bash
# Network status script for waybar (JSON output)

# Get WiFi info
WIFI_SSID=$(nmcli -t -f active,ssid dev wifi | grep '^yes:' | cut -d: -f2)
WIFI_SIGNAL=$(nmcli -t -f active,signal dev wifi | grep '^yes:' | cut -d: -f2)

if [[ -n "$WIFI_SSID" ]]; then
    echo "{\"text\":\" $WIFI_SIGNAL%\",\"tooltip\":\"$WIFI_SSID ($WIFI_SIGNAL%)\"}"
else
    # Check for ethernet
    ETH_CONN=$(nmcli -t -f type,state dev | grep 'ethernet:connected' | head -1)
    if [[ -n "$ETH_CONN" ]]; then
        echo "{\"text\":\"  connected\",\"tooltip\":\"Ethernet connected\"}"
    else
        echo "{\"text\":\"  offline\",\"tooltip\":\"No network connection\"}"
    fi
fi
