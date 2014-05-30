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

$DEBUG && logger -t opennet_ugw_down.sh "starting for iface ${dev}"
$DEBUG && logger -t opennet_ugw_down.sh "removing network config for ${dev}"

uci -q delete network.on_${dev}
uci commit network

# reload new ubus rpc interface (see http://wiki.openwrt.org/doc/techref/ubus)
ubus call network reload

$DEBUG && logger -t opennet_ugw_down.sh "removing iterface ${dev} from config of firewall zone opennet"
uci -q set firewall.zone_opennet.network="$(uci get firewall.zone_opennet.network | \
        awk '{ x=1; while ( x<=NF ) { if ( $x != "on_'$dev'" ) { printf $x" "; } x++ } printf "\n"}')"
uci commit firewall

#  removing on_tapX (tapX) from firewall zone opennet
$DEBUG && logger -t opennet_ugw_down.sh "removing firewall-rules for ${dev}"
. "$IPKG_INSTROOT/lib/functions.sh"
. "$IPKG_INSTROOT/lib/firewall/core.sh"
fw_reload

$DEBUG && logger -t opennet_ugw_down.sh "removing iterface ${dev} from config of olsrd, restarting olsrd"
uci -q set olsrd.@Interface[0].interface="$(uci get olsrd.@Interface[0].interface | \
        awk '{ x=1; while ( x<=NF ) { if ( $x != "on_'$dev'" ) { printf $x" "; } x++ } printf "\n"}')"
uci commit olsrd
/etc/init.d/olsrd restart

filename=/tmp/opennet_ugw-${remote_1}.txt
rm -f "$filename"    # removing running message

$DEBUG && logger -t opennet_ugw_down.sh "finished for iface ${dev}"

exit 0

