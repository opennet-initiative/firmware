#!/bin/sh

set -eu

# shellcheck source=opennet/packages/on-core/files/usr/lib/opennet/on-helper.sh
. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"


DST_IP=$1


if [ "$#" -lt 1 ] || [ -z "$1" ]; then
   echo "Bad parameter! IP as parameter is needed."
   echo "e.g."
   echo "      $(basename) 192.168.0.33"
   echo
   exit 1
fi >&2


if echo "$DST_IP" | grep -q ":"; then
    format_string=' %2d | %-39s | %-7s | %s\n'
else
    format_string=' %2d | %-15s | %-7s | %s\n'
fi

position=1
{ get_traceroute "$DST_IP" | tr ',' '\n'; echo; } | while read -r ip; do
    main_ip=$(get_main_ip_for_ip "$ip")
    name=$(get_name_for_main_ip "$main_ip")
    # shellcheck disable=SC2059
    printf "$format_string" "$position" "$ip" "$name" "$(get_location_for_main_ip "$main_ip")"
    position=$((position + 1))
done
