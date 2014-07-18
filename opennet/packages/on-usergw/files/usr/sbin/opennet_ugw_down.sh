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

. "$IPKG_INSTROOT/usr/bin/on-helper.sh"

msg_debug "starting for iface ${dev}"
msg_debug "removing network config for ${dev}"

uci -q "delete network.on_${dev}"
uci commit network

# reload new ubus rpc interface (see http://wiki.openwrt.org/doc/techref/ubus)
ubus call network reload

msg_debug "removing iterface ${dev} from config of firewall zone opennet"
uci -q set firewall.zone_opennet.network="$(uci get firewall.zone_opennet.network | \
        awk '{ x=1; while ( x<=NF ) { if ( $x != "on_'$dev'" ) { printf $x" "; } x++ } printf "\n"}')"
uci commit firewall

# removing on_tapX (tapX) from firewall zone opennet
msg_debug "removing firewall-rules for ${dev}"
/etc/init.d/firewall reload

msg_debug "removing iterface ${dev} from config of olsrd, restarting olsrd"
uci -q set olsrd.@Interface[0].interface="$(uci get olsrd.@Interface[0].interface | \
        awk '{ x=1; while ( x<=NF ) { if ( $x != "on_'$dev'" ) { printf $x" "; } x++ } printf "\n"}')"
uci commit olsrd
/etc/init.d/olsrd restart

filename=/tmp/opennet_ugw-${remote_1}.txt
rm -f "$filename"    # removing running message

msg_debug "finished for iface ${dev}"

exit 0

