#!/bin/sh
#
# Opennet Firmware
# 
# Copyright 2010 Rene Ejury <opennet@absorb.it>
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
# 	http://www.apache.org/licenses/LICENSE-2.0
# 

. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"

MSG_FILE=/tmp/openvpn_msg.txt

if [ -e "$MSG_FILE" ]; then
	msg_info "running instance detected by $MSG_FILE. stopping"
	exit 1
fi
echo "vpn-tunnel active" >"$MSG_FILE"	# a short message for the web frontend


# wir muessen nicht mehr streng sein
set +e

ip route add default via "$route_vpn_gateway" table "$ROUTING_TABLE_ON_UPLINK"

# start dhcp-fwd early
# TODO: why? It should run automatically anyway ...
[ -f "/etc/init.d/dhcp-fwd" ] && /etc/init.d/dhcp-fwd start

# always finish with success
exit 0

