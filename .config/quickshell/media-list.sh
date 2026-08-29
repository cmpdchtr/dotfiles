#!/usr/bin/env bash

set -uo pipefail

readonly field_sep=$'\x1f'
readonly row_sep=$'\x1e'
first=1
while read -r name _; do
    case "$name" in
        org.mpris.MediaPlayer2.playerctld)
            # playerctld mirrors another MPRIS player and would otherwise show
            # the same application twice in the selector.
            continue
            ;;
        org.mpris.MediaPlayer2.*)
            identity=$(busctl --user get-property "$name" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2 Identity 2>/dev/null | sed -E 's/^s "(.*)"$/\1/')
            status=$(busctl --user get-property "$name" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player PlaybackStatus 2>/dev/null | sed -E 's/^s "(.*)"$/\1/')
            identity=$(printf '%b' "$identity")
            [[ -z "$identity" ]] && identity=${name##*.}
            [[ $first -eq 0 ]] && printf '%s' "$row_sep"
            printf '%s%s%s%s%s' "$name" "$field_sep" "$identity" "$field_sep" "$status"
            first=0
            ;;
    esac
done < <(busctl --user --no-pager --no-legend list 2>/dev/null)
printf '\n'
