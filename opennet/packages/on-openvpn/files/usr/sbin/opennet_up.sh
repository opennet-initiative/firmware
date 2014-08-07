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

. "${IPKG_INSTROOT:-}/usr/bin/on-helper.sh"

MSG_FILE=/tmp/openvpn_msg.txt

if [ -e "$MSG_FILE" ]; then
	msg_info "running instance detected by $MSG_FILE. stopping"
	exit 1
fi
echo "vpn-tunnel active" >"$MSG_FILE"	# a short message for the web frontend

if [ -z "$(ip rule show | grep "lookup tun")" ];then
	mainprio=$(ip rule show | awk 'BEGIN{FS="[: ]"} /main/ {print $1; exit}')
	for network in $(uci get -q firewall.zone_local.network) $(uci get -q firewall.zone_free.network); do
		networkprefix=$(get_network "$network")
		[ -n "$networkprefix" ] && ip rule add from "$networkprefix" table tun prio "$((mainprio+10))"
	done
	ip rule add iif lo table tun prio "$((mainprio+10))"
fi

ip route flush table tun
# prefer olsrd-routes for main and tunnel network
for network in $(uci get on-core.defaults.on_network); do
	ip route prepend throw "$network" table tun
done
ip route add default via "$route_vpn_gateway" table tun

# start dhcp-fwd early
# TODO: why? It should run automatically anyway ...
[ -f "/etc/init.d/dhcp-fwd" ] && /etc/init.d/dhcp-fwd start

# Empty or non-existing nameserver file? Discover opennet nameservers immediately ...
[ ! -s "/tmp/resolv.conf.auto" ] && update_dns_servers

# always finish with success
exit 0

