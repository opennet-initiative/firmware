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
	"$DEBUG" && logger -t "$(basename "$0")[$$]" "$1" || true
}

msg_info() {
	logger -t "$(basename "$0")[$$]" "$1"
}

# update a file if its content changed
# return exitcode=0 (success) if the file was updated
# return exitcode=1 (failure) if there was no change
_update_file_if_changed() {
	local target_filename="$1"
	local content="$(cat -)"
	if [ -e "$target_filename" ] && echo "$content" | cmp -s - "$target_filename"; then
		# the content did not change
		return 1
	else
		# updated content
		echo "$content" > "$target_filename"
		return 0
	fi
}

# Gather the list of routable IPs specified via on-core.services.dns_ip_regex.
# Store this list as a resolv.conf-compatible file in on-core.services.dns_resolv_file. 
# The file is only updated in case of changes.
update_dns_servers() {
	local dns_ip_regex="$(uci -q get on-core.services.dns_ip_regex)"
	local dns_resolv_file="$(uci -q get on-core.services.dns_resolv_file)"
	# quit if no regex is given
	[ -z "$dns_ip_regex" -o -z "$dns_resolv_file" ] && return 1
	# create temporary resolv.conf.auto file
	(
		echo "# nameservers added by opennet firmware"
		echo "# see: uci get on-core.services.dns_ip_regex"
		get_mesh_ips_by_regex "$dns_ip_regex" | sort | while read ip; do
			echo "nameserver $ip 	# added by on-helper/update_dns_servers"
		done
	) | _update_file_if_changed "$dns_resolv_file" && msg_info "updating DNS entries"
	return
}

# Gather the list of routable IPs specified via on-core.services.ntp_ip_regex.
# Store this list as ntpclient-compatible uci settings. 
# The uci settings are only updated in case of changes.
# ntpclient is restarted in case of changes.
update_ntp_servers() {
	local ntp_ip_regex="$(uci -q get on-core.services.ntp_ip_regex)"
	# quit if no regex is given
	[ -z "$ntp_ip_regex" ] && return 1
	local current_servers="$(uci show ntpclient | grep "\.hostname=" | cut -f 2- -d = | sort)"
	local new_servers="$(get_mesh_ips_by_regex "$ntp_ip_regex" | sort)"
	local section_name=
	if [ "$current_servers" != "$new_servers" ]; then
		# delete all current servers
		while uci -q delete ntpclient.@ntpserver[0]; do true; done
		for ip in $new_servers; do
			section_name="$(uci add ntpclient ntpserver)"
			uci set "ntpclient.${section_name}.hostname=$ip"
			uci set "ntpclient.${section_name}.port=123"
		done
		msg_info "updating NTP entries"
		uci commit ntpclient
		control_ntpclient restart
	fi
	# make sure that ntpclient is running (in case it broke before)
	if [ -z "$(pidof ntpclient)" ]; then
		msg_info "'ntpclient' is not running: starting it again ..."
		control_ntpclient start
	fi
	return
}

# stop and start ntpclient
# This should be used whenever the list of ntp server changes.
# BEWARE: this function depends on internals of ntpclient's hotplug script
control_ntpclient() {
	local action="$1"
	local ntpclient_script="$(find /etc/hotplug.d/iface/ -type f | grep ntpclient | head -n 1)"
	[ -z "$ntpclient_script" ] && msg_info "error: failed to find ntpclient hotplug script" && return 0
	. "$ntpclient_script"
	case "$action" in
		start)
			start_ntpclient
			;;
		stop)
			stop_ntpclient
			;;
		restart)
			stop_ntpclient
			start_ntpclient
			;;
		*)
			echo >&2 "ERROR: unknown action for 'control_ntpclient': $action"
			;;
	esac
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
	# set root password
	echo "root:admin" | chpasswd
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

# find all routes matching a given regex
# remove trailing "/32"
get_mesh_ips_by_regex() {
	local regex="$1"
	echo /route | nc localhost 2006 | grep "^[0-9\.]\+" | awk '{print $1}' | sed 's#/32$##' | grep "$regex"
}

