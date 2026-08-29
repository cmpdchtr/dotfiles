#!/usr/bin/env bash

set -uo pipefail

mode=${1:-screen}
with_audio=${2:-no}
recordings_dir=${XDG_VIDEOS_DIR:-"$HOME/Videos"}/Recordings
mkdir -p "$recordings_dir"

args=(-r 60)
if [[ "$mode" == area ]]; then
    geometry=$(slurp) || exit 0
    [[ -n "$geometry" ]] || exit 0
    args+=(-g "$geometry")
fi

if [[ "$with_audio" == yes ]]; then
    sink_name=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null \
        | sed -nE 's/^[[:space:]]*\*?[[:space:]]*node\.name = "([^"]+)"/\1/p' \
        | head -n 1)
    if [[ -n "$sink_name" ]]; then
        args+=(--audio="${sink_name}.monitor")
    else
        notify-send "Screen recorder" "Could not find the system audio output" 2>/dev/null || true
        exit 1
    fi
fi

output="$recordings_dir/recording_$(date +%Y%m%d_%H%M%S).mp4"
exec wf-recorder "${args[@]}" -f "$output"
