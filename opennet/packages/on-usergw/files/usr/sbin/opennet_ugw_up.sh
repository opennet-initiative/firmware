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
#   http://www.apache.org/licenses/LICENSE-2.0
# 

# retrieve DEBUG-state
DEBUG=$(uci -q get on-core.defaults.debug)

. "$IPKG_INSTROOT/lib/functions.sh"

# newline
N="
"
$DEBUG && logger -t opennet_ugw_up.sh "starting for iface ${dev}"

local batch
# add new network to configuration (to be recognized by olsrd)
append batch "set network.on_${dev}=interface${N}"
append batch "set network.on_${dev}.proto=static${N}"
append batch "set network.on_${dev}.ifname=${dev}${N}"
append batch "set network.on_${dev}.netmask=${ifconfig_netmask}${N}"
append batch "set network.on_${dev}.ipaddr=${ifconfig_local}${N}"
append batch "set network.on_${dev}.defaultroute=0${N}"
append batch "set network.on_${dev}.peerdns=0${N}"

$DEBUG && logger -t opennet_ugw_up.sh "adding new network config for ${dev}"
        
echo "$batch${N}commit network" | uci batch

# reload new ubus rpc interface (see http://wiki.openwrt.org/doc/techref/ubus)
ubus call network reload

zone_on_ifaces="$(uci -q get firewall.zone_opennet.network)";
if [ -z "$(echo $zone_on_ifaces | grep on_${dev})" ]; then
	$DEBUG && logger -t opennet_ugw_up.sh "adding interface ${dev} to config of firewall zone opennet"
	uci -q set firewall.zone_opennet.network="$(uci -q get firewall.zone_opennet.network) on_${dev}"
	uci commit firewall
	$DEBUG && logger -t opennet_ugw_down.sh "applying updated firewall rules for ${dev}"
	/etc/init.d/firewall reload
fi


olsrd_ifaces="$(uci -q get olsrd.@Interface[0].interface)";
if [ -z "$(echo $olsrd_ifaces | grep on_${dev})" ]; then
	$DEBUG && logger -t opennet_ugw_up.sh "adding iterface ${dev} to config of olsrd, restarting olsrd"
	uci -q set olsrd.@Interface[0].interface="${olsrd_ifaces} on_${dev}"
	uci commit olsrd
	/etc/init.d/olsrd restart
fi


filename=/tmp/opennet_ugw-${remote_1}.txt
echo "$dev" > "$filename" # a short message for the web frontend

$DEBUG && logger -t opennet_ugw_up.sh "finished for iface ${dev}"

exit 0

