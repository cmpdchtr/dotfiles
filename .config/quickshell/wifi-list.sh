#!/usr/bin/env bash

set -uo pipefail

readonly field_sep=$'\x1f'
readonly row_sep=$'\x1e'
readonly escaped_colon=$'\x1d'

declare -A saved=()
while IFS= read -r line; do
    line=${line//\\:/$escaped_colon}
    IFS=: read -r name type <<< "$line"
    name=${name//$escaped_colon/:}
    if [[ "$type" == "802-11-wireless" ]]; then
        ssid=$(nmcli -g 802-11-wireless.ssid connection show "$name" 2>/dev/null | head -n 1)
        saved["${ssid:-$name}"]=$name
    fi
done < <(nmcli -t --escape yes -f NAME,TYPE connection show 2>/dev/null)

first=1
declare -A seen=()
while IFS= read -r line; do
    line=${line//\\:/$escaped_colon}
    IFS=: read -r in_use ssid signal security <<< "$line"
    ssid=${ssid//$escaped_colon/:}
    [[ -z "$ssid" || -n "${seen[$ssid]:-}" ]] && continue
    seen["$ssid"]=yes
    [[ $first -eq 0 ]] && printf '%s' "$row_sep"
    printf '%s%s%s%s%s%s%s%s%s' \
        "$ssid" "$field_sep" "$signal" "$field_sep" "${security:---}" "$field_sep" \
        "$([[ "$in_use" == "*" ]] && echo yes || echo no)" "$field_sep" \
        "${saved[$ssid]:-}"
    first=0
done < <(nmcli -t --escape yes -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan no 2>/dev/null)
printf '\n'
