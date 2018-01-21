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
  location=$(wget -q -O - http://api.on/api/v1/accesspoint/$ip | awk 'BEGIN { FS = "post_address\":\"" } ; { print $2 }' | cut -d"\"" -f1)
  echo -n "$location"
}

traceroute "$dst_ip" | tr '*' ' ' | while read line; do

  #ignore first line "traceroute to ...."
  tmp=$(echo $line | awk '{print substr($0,0,13)}')
  if [ "$tmp" = "traceroute to" ]; then
    continue
  fi

  num=$(echo "$line" | awk '{ print $1 }')
  dns=$(echo "$line" | awk '{ print $2 }')
  ip=$(echo "$line" | awk '{ print $3 }')
  ip=${ip%)} #delete last ")"
  ip=${ip#(} #delete first "("

  first_num=$(echo $ip | cut -d"." -f1 )
  if [ "$first_num" = "192" -o "$first_num" = "10" ]; then # "-o" means "or" here
    #only process 10.x.y.z and 192.168.x.y.z IPs. Ignore 172.x.y.z and lines with "*" symbol
    # fetch location name
    echo -n " $num - IP: $ip - Location: "
    get_location_from_api $ip
    echo " - DNS: $dns"
  fi
done

