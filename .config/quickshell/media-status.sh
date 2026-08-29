#!/usr/bin/env bash

set -uo pipefail

readonly field_sep=$'\x1f'
preferred=${1:-}
selected=""
fallback=""

while read -r name _; do
    case "$name" in
        org.mpris.MediaPlayer2.playerctld)
            # This is a proxy for a real player, not a separate media source.
            continue
            ;;
        org.mpris.MediaPlayer2.*)
            [[ -z "$fallback" ]] && fallback=$name
            if [[ -n "$preferred" && "$name" == "$preferred" ]]; then
                selected=$name
                break
            fi
            state=$(busctl --user get-property "$name" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player PlaybackStatus 2>/dev/null)
            if [[ -z "$preferred" && "$state" == *Playing* ]]; then
                selected=$name
                break
            fi
            ;;
    esac
done < <(busctl --user --no-pager --no-legend list 2>/dev/null)

[[ -z "$selected" ]] && selected=$fallback
if [[ -z "$selected" ]]; then
    printf 'Stopped%sNothing playing%sOpen a player to see it here%s%s%s0%sMedia\n' \
        "$field_sep" "$field_sep" "$field_sep" "$field_sep" "$field_sep" "$field_sep"
    exit 0
fi

status=$(busctl --user get-property "$selected" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player PlaybackStatus 2>/dev/null | sed -E 's/^s "(.*)"$/\1/')
identity=$(busctl --user get-property "$selected" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2 Identity 2>/dev/null | sed -E 's/^s "(.*)"$/\1/')
metadata=$(busctl --user get-property "$selected" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Metadata 2>/dev/null)
title=$(printf '%s' "$metadata" | sed -nE 's/.*"xesam:title" s "([^"]*)".*/\1/p')
artist=$(printf '%s' "$metadata" | sed -nE 's/.*"xesam:artist" as [0-9]+ "([^"]*)".*/\1/p')
art=$(printf '%s' "$metadata" | sed -nE 's/.*"mpris:artUrl" s "([^"]*)".*/\1/p')
length=$(printf '%s' "$metadata" | sed -nE 's/.*"mpris:length" [a-z] ([0-9]+).*/\1/p')

title=$(printf '%b' "$title")
artist=$(printf '%b' "$artist")
identity=$(printf '%b' "$identity")
[[ -z "$title" ]] && title='Unknown title'
[[ -z "$artist" ]] && artist='Unknown artist'
[[ -z "$identity" ]] && identity='Media'
[[ -z "$length" ]] && length=0

printf '%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
    "$status" "$field_sep" "$title" "$field_sep" "$artist" "$field_sep" \
    "$selected" "$field_sep" "$art" "$field_sep" "$length" "$field_sep" "$identity"
