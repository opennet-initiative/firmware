#!/bin/sh

set -eu

dst_ip=$1

if [ "$#" -lt 1 ] || [ -z "$1" ]; then
   echo "Bad parameter! IP as parameter is needed."
   echo "e.g."
   echo "      traceroute-oni.sh 192.168.0.33"
   echo
   exit 1
fi >&2


get_location_from_api() {
  local ip="$1"
  #extract value of post_address
  # sample input:   "post_address":"xyz"
  # sample output:  xyz
  wget -q -O - "http://api.opennet-initiative.de/api/v1/accesspoint/$ip" | awk 'BEGIN { FS = "post_address\":\"" } ; { print $2 }' | cut -d '"' -f 1
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

  # handle only Opennet IPs (10.0.0.0/8 or 192.168.0.0/16)
  if echo "$ip" | grep -qE '^(10|192\.168)\.'; then
    # fetch location name
    printf ' %s - IP: %s - Location: %s - DNS: %s\n' \
        "$num" "$ip" "$(get_location_from_api "$ip")" "$dns"
  fi
done
