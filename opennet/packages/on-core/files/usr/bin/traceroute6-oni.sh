#!/bin/sh

. ./olsr2.sh

set -eu

if [ "$#" -lt 1 ] || [ -z "$1" ]; then
   echo "Bad parameter! IP as parameter is needed."
   echo "e.g."
   echo "      traceroute6-oni.sh fd32:d8d3:87da::245"
   echo
   exit 1
fi >&2

dst_ip=$1

get_location_from_api() {
  local ip="$1"
  #extract value of post_address
  # sample input:   "post_address":"xyz"
  # sample output:  xyz
  wget -q -O - "http://api.on/api/v1/accesspoint/$ip" | awk 'BEGIN { FS = "post_address\":\"" } ; { print $2 }' | cut -d '"' -f 1
}

traceroute "$dst_ip" | tr '*' ' ' | while read -r line; do

  #ignore first line "traceroute to ...."
  tmp=$(echo "$line" | awk '{print substr($0,0,13)}')
  if [ "$tmp" = "traceroute to" ]; then
    continue
  fi

  num=$(echo "$line" | awk '{ print $1 }')
  dns=$(echo "$line" | awk '{ print $2 }')
  ip=$(echo "$line" | awk '{ print $3 }')
  ip=${ip%)} #delete last ")"
  ip=${ip#(} #delete first "("
  if [ "$dns" = "$ip" ]; then
    dns="-" #no reverse dns possible
  fi

  # handle only Opennet IPs (fd32:d8d3:87da::/64)
  if echo "$ip" | grep -qE '^(fd32:d8d3:87da)'; then
    # fetch location name
    ipv4="$(debug_fetch_ipv4_from_ipv6_for_ap $ip)"
    printf ' %s - IPv6: %s - IPv4: %s - Location: %s - DNS: %s\n' \
        "$num" "$ip" "$ipv4" "$(get_location_from_api "$ipv4")" "$dns"
  fi
done
