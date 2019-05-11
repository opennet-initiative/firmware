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


get_ap_name_from_main_ip() {
    local main_ip="$1"
    if echo "$main_ip" | grep -q '^192\.168\.'; then
        echo "AP${main_ip#192.168.}"
    else
        echo "$main_ip"
    fi
}


get_location_from_api() {
    local main_ip="$1"
    # extract value of "post_address" via API
    wget -q -O - "$OPENNET_API_URL/accesspoint/$main_ip" | jsonfilter -e '@.post_address'
}


if echo "$DST_IP" | grep -q ":"; then
    format_string=' %2d | %-39s | %-7s | %s\n'
else
    format_string=' %2d | %-15s | %-7s | %s\n'
fi

position=1
{ get_traceroute "$DST_IP" | tr ',' '\n'; echo; } | while read -r ip; do
    if [ -n "${IP6_PREFIX_PERM:-}" ] && echo "$ip" | grep -q "^$IP6_PREFIX_PERM:"; then
        # Opennet IPv6 addresses
        main_ip="$(debug_ipv4_main_ip_from_ipv6_for_ap "$ip")"
    elif echo "$ip" | grep -qE '^(10|192\.168)\.'; then
        # Opennet IPv4 addresses (10.0.0.0/8 or 192.168.0.0/16)
        main_ip=$(wget -q -O - "$OPENNET_API_URL/interface/$ip" | jsonfilter -e '@.accesspoint')
    else
        continue
    fi
    name=$(get_ap_name_from_main_ip "$main_ip")
    # shellcheck disable=SC2059
    printf "$format_string" "$position" "$ip" "$name" "$(get_location_from_api "$main_ip")"
    position=$((position + 1))
done
