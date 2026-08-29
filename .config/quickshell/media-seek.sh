#!/usr/bin/env bash

set -uo pipefail

service=${1:-}
target_us=${2:-0}
[[ -n "$service" && "$target_us" =~ ^[0-9]+$ ]] || exit 2

object=/org/mpris/MediaPlayer2
player=org.mpris.MediaPlayer2.Player
player_name=${service#org.mpris.MediaPlayer2.}
target_seconds=$(awk -v value="$target_us" 'BEGIN { printf "%.6f", value / 1000000 }')

# Chromium-based players can acknowledge SetPosition while silently ignoring
# backward seeks. playerctl handles those MPRIS quirks and reports failures.
if command -v playerctl >/dev/null 2>&1 \
    && playerctl --player="$player_name" position "$target_seconds" >/dev/null 2>&1; then
    exit 0
fi

metadata=$(busctl --user get-property "$service" "$object" "$player" Metadata 2>/dev/null) || exit 1
track_id=$(printf '%s' "$metadata" | sed -nE 's/.*"mpris:trackid" o "([^"]+)".*/\1/p')

if [[ -n "$track_id" ]] && busctl --user call "$service" "$object" "$player" SetPosition ox "$track_id" "$target_us" >/dev/null 2>&1; then
    exit 0
fi

current_us=$(busctl --user get-property "$service" "$object" "$player" Position 2>/dev/null | awk '{print $2}')
[[ "$current_us" =~ ^[0-9]+$ ]] || current_us=0
busctl --user call "$service" "$object" "$player" Seek x "$((target_us - current_us))" >/dev/null
