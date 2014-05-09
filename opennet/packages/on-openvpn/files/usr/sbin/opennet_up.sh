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

if [ -e /tmp/openvpn_msg.txt ]; then
	logger -t "openvpn opennet_up" "running instance detected by /tmp/openvpn_msg.txt. stopping"
	exit 1
fi
echo "vpn-tunnel active" >/tmp/openvpn_msg.txt	# a short message for the web frontend

. $IPKG_INSTROOT/usr/bin/on-helper.sh

if [ -z "$(ip rule show | grep "lookup tun")" ];then
    mainprio=$(ip rule show | awk 'BEGIN{FS="[: ]"} /main/ {print $1; exit}')
	for network in $(echo "$(uci get -q firewall.zone_local.network) $(uci get -q firewall.zone_free.network)"); do
        networkprefix=$(get_network $network)
        [ -n "$networkprefix" ] && ip rule add from $networkprefix table tun prio $((mainprio+10))
    done
	ip rule add iif lo table tun prio $((mainprio+10))
fi

ip route flush table tun
#   prefer olsrd-routes for main and tunnel network
for network in $(uci get on-core.defaults.on_network); do
    ip route prepend throw $network table tun
done
ip route add default via $route_vpn_gateway table tun

if [ -f "/etc/init.d/dhcp-fwd" ]; then
	. /etc/init.d/dhcp-fwd
	start &
fi

# At the beginning of system start /etc/resolv.conf.auto is not available or size=0. In that case start service
if [ ! -e "/tmp/resolv.conf.auto" -o ! -s "/tmp/resolv.conf.auto" ]; then
        update_dns_servers                
fi
