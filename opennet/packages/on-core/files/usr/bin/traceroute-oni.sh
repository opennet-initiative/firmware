#!/bin/sh

set -eu

. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"


DST_IP=$1


if [ "$#" -lt 1 ] || [ -z "$1" ]; then
   echo "Bad parameter! IP as parameter is needed."
   echo "e.g."
   echo "      $(basename) 192.168.0.33"
   echo
   exit 1
fi >&2


get_location_for_ap_name_or_ip() {
    local name="$1"
    local ip="$2"
    local ap_data
    if echo "$name" | grep -q "^AP"; then
        ip=$(echo "$name" | sed -E 's/^AP(\d+)-(\d+)$/192.168.\1.\2/')
    fi
    # extract value of "post_address" via API
    ap_data=$(wget -q -O - "$OPENNET_API_URL/accesspoint/$ip")
    [ -z "$ap_data" ] && return
    echo "$ap_data" | jsonfilter -e '@.post_address'
}


if echo "$DST_IP" | grep -q ":"; then
    format_string=' %2d | %-39s | %-7s | %s\n'
else
    format_string=' %2d | %-15s | %-7s | %s\n'
fi

position=1
{ get_traceroute "$DST_IP" | tr ',' '\n'; echo; } | while read -r ip; do
    name=$(get_ap_name_for_ip "$ip")
    # shellcheck disable=SC2059
    printf "$format_string" "$position" "$ip" "$name" "$(get_location_for_ap_name_or_ip "$name" "$ip")"
    position=$((position + 1))
done
