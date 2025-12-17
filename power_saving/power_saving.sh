#!/bin/bash

logger "Power-Saver Started."

rfkill unblock wifi

logger "Power-Saver waiting 1 minute for wifi connection."
sleep 60

if wpa_cli -i wlan0 status | grep -q "wpa_state=COMPLETED"; then

    SSID=$(wpa_cli -i wlan0 status | grep "^ssid=" | cut -d= -f2)
    logger "Power-Saver: Connected to '$SSID'. WiFi stays ON."
    exit 0

else

    logger "Power-Saver: No WiFi connection detected. Turning OFF Radio."
    rfkill block wifi
    exit 0

fi
