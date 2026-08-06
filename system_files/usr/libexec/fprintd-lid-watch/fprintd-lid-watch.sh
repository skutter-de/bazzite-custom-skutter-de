#!/bin/bash
# Deaktiviert den internen Fingerabdruckleser, solange der Laptop-Deckel
# geschlossen ist (z.B. am Dock mit externem Monitor/Tastatur), damit
# GDM/polkit nicht auf einen unerreichbaren Fingerabdruck warten und
# sofort das Passwortfeld nutzbar ist.
#
# Fingerprint-Reader: Synaptics Prometheus MIS Touch (idVendor 06cb, idProduct 00bd)
set -uo pipefail

VENDOR="06cb"
PRODUCT="00bd"

find_usb_path() {
    for d in /sys/bus/usb/devices/*/idVendor; do
        local v p
        v=$(cat "$d" 2>/dev/null)
        p=$(cat "$(dirname "$d")/idProduct" 2>/dev/null)
        if [ "$v" = "$VENDOR" ] && [ "$p" = "$PRODUCT" ]; then
            dirname "$d"
            return 0
        fi
    done
    return 1
}

apply_state() {
    local closed="$1"
    local path
    path=$(find_usb_path) || { logger -t fprintd-lid-watch "Fingerprint-Reader nicht gefunden"; return; }

    local current
    current=$(cat "$path/authorized" 2>/dev/null)

    if [ "$closed" = "true" ]; then
        if [ "$current" = "1" ]; then
            logger -t fprintd-lid-watch "Deckel zu: deaktiviere Fingerabdruckleser ($path)"
            echo 0 > "$path/authorized" 2>/dev/null
        fi
    else
        if [ "$current" = "0" ]; then
            logger -t fprintd-lid-watch "Deckel auf: aktiviere Fingerabdruckleser ($path)"
            echo 1 > "$path/authorized" 2>/dev/null
        fi
    fi
}

get_lid_state() {
    busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
        org.freedesktop.login1.Manager LidClosed 2>/dev/null | awk '{print $2}'
}

# initialen Zustand direkt anwenden
apply_state "$(get_lid_state)"

# und danach auf Änderungen reagieren
gdbus monitor --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 2>/dev/null | \
while read -r line; do
    if echo "$line" | grep -q "LidClosed"; then
        state=$(get_lid_state)
        apply_state "$state"
    fi
done
