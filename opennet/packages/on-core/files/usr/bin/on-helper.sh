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
#	http://www.apache.org/licenses/LICENSE-2.0
# 

#################################################################################
# just to get the IP for gateways only registered by name
# parameter is name
query_dns() { nslookup $1 2>/dev/null | tail -n 1 | awk '{ print $3 }'; }

query_dns_reverse() { nslookup $1 2>/dev/null | tail -n 1 | awk '{ print $4 }'; }

get_client_cn() {
	openssl x509 -in /etc/openvpn/opennet_user/on_aps.crt \
		-subject -nameopt multiline -noout 2>/dev/null | awk '/commonName/ {print $3}'
}

DEBUG=$(uci -q get on-core.defaults.debug)
msg_debug() {
	$DEBUG && logger -t $(basename "$0")[$$] "$1" || true
}

msg_info() {
	logger -t $(basename "$0")[$$] "$1"
}

update_dns_from_gws()
{
	# TODO: Abhaengigkeit von on-openvpn loesen; regelmaessig aufrufen
	if $(uci -q get on-openvpn.gateways.gw_dns) && [ -n "$current_gws" ]; then
		(
		echo "# nameserver added by opennet firmware"
		echo "# check (uci on-core.settings.gw_dns)"
		for gw in $current_gws; do
			echo "nameserver $gw # added by on_vpngateway_check"
		done
		) >/tmp/resolv.conf.auto-generating
		if cmp -s /tmp/resolv.conf.auto /tmp/resolv.conf.auto-generating; then
			rm /tmp/resolv.conf.auto-generating
		else
			msg_debug "updating DNS entries"
			mv /tmp/resolv.conf.auto-generating /tmp/resolv.conf.auto
		fi
	fi
}

update_ntp_from_gws() {
	# TODO: Abhaengigkeit von on-openvpn loesen; regelmaessig aufrufen
	if $(uci -q get on-openvpn.gateways.gw_ntp) && [ -n "$current_gws" ]; then
		update_required=false
		no=0
		for gw in $current_gws; do
			if [ -n "$(uci -q get ntpclient.@ntpserver[${no}])" ]; then
				if [ "$(uci -q get ntpclient.@ntpserver[${no}].hostname)" != "$gw" ]; then
					update_required=true
					uci -q set ntpclient.@ntpserver[${no}].hostname=$gw
					uci -q set ntpclient.@ntpserver[${no}].port=123
				fi
			else
				update_required=true;
				item=$(uci add ntpclient ntpserver)
				uci -q set ntpclient.${item}.hostname=$gw;
				uci -q set ntpclient.${item}.port=123;
			fi
			: $((no++))
		done
		while [ -n "$(uci -q get ntpclient.@ntpserver[${no}])" ]; do
			uci delete ntpclient.@ntpserver[${no}]
		done
		if $update_required; then
			msg_debug "updating NTP entries"
			uci commit ntpclient
			/etc/init.d/ntpclient start
		fi
	fi
}

get_network() {
# 	if [ "$(uci -q get network.$1.type)" == "bridge" ]; then
# 		ifname="br-$1"
# 	else
# 		ifname=$(uci -q get network.$1.ifname)
# 	fi
	. "$IPKG_INSTROOT/lib/functions.sh"
	include "$IPKG_INSTROOT/lib/network"
	scan_interfaces
	ifname="$(config_get $1 ifname)"
	if [ -n "$ifname" ] && [ "$ifname" != "none" ]; then                   
		ipaddr="$(ip address show label "$ifname" | awk '/inet/ {print $2; exit}')"
		[ -z "$ipaddr" ] || { eval $(ipcalc -p -n "$ipaddr"); echo $NETWORK/$PREFIX; }
	fi
}

check_firmware_upgrade() {
	old_version=$(awk '{if (/opennet-firmware-ng/) print $4}' /etc/banner)
	cur_version=$(opkg status on-core | awk '{if (/Version/) print $2;}')
	if [ "$old_version" != "$cur_version" ]; then
		copy_etc_presets
		# copy banner, somehow this has to be done explicit (at least) for 0.4-2
		cp /rom/etc/banner /etc/banner
		add_banner
		# this only triggers if on-usergw is installed, great
		lua -e "require('luci.model.opennet.on_usergw') upgrade()" 2>/dev/null
	fi
	if [ -z "$(uci show olsrd | grep ondataservice)" ]; then
		# add and activate ondataservice plugin
		section=$(uci add olsrd LoadPlugin)
		uci set olsrd.$section.library=olsrd_ondataservice_light.so.0.1
		uci set olsrd.$section.interval=10800
		uci set olsrd.$section.inc_interval=5
		uci set olsrd.$section.database=/tmp/database.json
		uci commit olsrd
	fi
}

copy_etc_presets() {
	ln -sf /etc/etc_presets/passwd /etc/passwd
	ln -sf /etc/etc_presets/rc.local /etc/rc.local
	ln -sf /etc/etc_presets/watchdog /etc/init.d/watchdog
}

copy_config_presets() {
	for preset in /etc/config_presets/*; do
		if [ "$1" == "force" ]; then
			cp $preset /etc/config/${preset#/*/*/};
		else
			[ -f /etc/config/${preset#/*/*/} ] || cp $preset /etc/config/${preset#/*/*/};
		fi
	done
}

add_banner() {
	version=$(opkg status on-core | awk '{if (/Version/) print $2;}')
	version_line=" ---- with opennet-firmware-ng "$version" "
	empty_line=" "
	while [ ${#version_line} -lt 54 ]; do version_line="$version_line-"; done
	while [ ${#empty_line} -lt 54 ]; do empty_line="$empty_line-"; done

	awk '
		BEGIN{ tagged=0 }
		{
			if ($0 ~ /opennet-firmware/) {
			tagged=1; print "'"$version_line"'";
		}
			else print $0
		}
		END{ if (tagged == 0) print "'"$version_line"'\n'"$empty_line"'"}' /etc/banner >/tmp/banner

	mv /tmp/banner /etc/banner
}

# $1 is on_id, $2 is on_ipschema, $3 is no
get_on_ip() {
	on_id=$1
	on_ipschema=$2
	no=$3
	# split into two seperate fields
	on_id_1=$(echo $on_id | cut -d"." -f1)
	on_id_2=$(echo $on_id | cut -d"." -f2)
	if [ -z "$on_id_2" ]; then
		on_id_2=on_id_1
		on_id_1=1
	fi
	echo $(eval echo $on_ipschema)
}

