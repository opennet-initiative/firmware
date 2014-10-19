#!/bin/sh
#
# Opennet Firmware
# 
# Copyright 2010 Rene Ejury <opennet@absorb.it>
# Copyright 2014 Lars Kruse <devel@sumpfralle.de>
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#	http://www.apache.org/licenses/LICENSE-2.0
# 

set -eu

GATEWAY_STATUS_FILE=/tmp/on-openvpn_gateways.status
UGW_STATUS_FILE=/tmp/on-ugw_gateways.status
ON_DEFAULTS_FILE=/usr/share/opennet/defaults.txt
SERVICES_FILE=/var/run/services_olsr
DNSMASQ_SERVERS_FILE_DEFAULT=/var/run/dnsmasq.servers
OLSR_POLICY_DEFAULT_PRIORITY=65535

DEBUG=$(uci -q get on-core.defaults.debug || echo false)


#################################################################################
# just to get the IP for gateways only registered by name
# parameter is name
query_dns() { nslookup $1 2>/dev/null | tail -n 1 | awk '{ printf "%s", $3 }'; }

query_dns_reverse() { nslookup $1 2>/dev/null | tail -n 1 | awk '{ printf "%s", $4 }'; }

get_client_cn() {
	openssl x509 -in /etc/openvpn/opennet_user/on_aps.crt \
		-subject -nameopt multiline -noout 2>/dev/null | awk '/commonName/ {print $3}'
}

msg_debug() {
	"$DEBUG" && logger -t "$(basename "$0")[$$]" "$1" || true
}

msg_info() {
	logger -t "$(basename "$0")[$$]" "$1"
}

# update a file if its content changed
# return exitcode=0 (success) if the file was updated
# return exitcode=1 (failure) if there was no change
update_file_if_changed() {
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


uci_is_true() {
	uci_is_false "$1" && return 1
	return 0
}


uci_is_false() {
	local token=$1
	[ "$token" = "0" -o "$token" = "no" -o "$token" = "off" -o "$token" = "false" ] && return 0
	return 1
}


# "uci -q get ..." endet mit einem Fehlercode falls das Objekt nicht existiert
# Dies erschwert bei strikter Fehlerpruefung (set -e) die Abfrage von uci-Werten.
# Die Funktion "uci_get" liefert bei fehlenden Objekten einen leeren String zurueck
# oder den gegebenen Standardwert zurueck.
# Der Exitcode signalisiert immer Erfolg.
# Syntax:
#   uci_get firewall.zone_free.masq 1
# Der abschließende Standardwert (zweiter Parameter) ist optional.
uci_get() {
	local key=$1
	local default=${2:-}
	if uci -q "$key"; then
		return 0
	else
		[ -n "$default" ] && echo "$default"
		return 0
	fi
}


# Gather the list of hosts announcing a NTP services.
# Store this list as a dnsmasq 'server-file'.
# The file is only updated in case of changes.
update_dns_servers() {
	local use_dns="$(uci_get on-core.services.use_olsrd_dns)"
	# return if we should not use DNS servers provided via olsrd
	uci_is_false "$use_dns" && return
	local servers_file=$(uci_get "dhcp.@dnsmasq[0].serversfile")
	if [ -z "$servers_file" ]; then
	       servers_file=$DNSMASQ_SERVERS_FILE_DEFAULT
	       uci set "dhcp.@dnsmasq[0].serversfile=$servers_file"
	       uci commit "dhcp.@dnsmasq[0]"
	       /etc/init.d/dnsmasq restart
	fi
	# replace ":" with "#" (dnsmasq expects this port separator)
	get_services dns | sed 's/^\([0-9\.]\+\):/\1#/' | sort | while read host other; do
		echo "server=$host"
	done | update_file_if_changed "$servers_file" \
		&& msg_info "updating DNS servers" \
		&& killall -s HUP dnsmasq	# reload config
	return
}

# Gather the list of hosts announcing a NTP services.
# Store this list as ntpclient-compatible uci settings.
# The uci settings are only updated in case of changes.
# ntpclient is restarted in case of changes.
update_ntp_servers() {
	local use_ntp="$(uci_get on-core.services.use_olsrd_ntp)"
	# return if we should not use NTP servers provided via olsrd
	uci_is_false "$use_ntp" && return
	# separate host and port with whitespace
	local ntp_services=$(get_services ntp | sed 's/^\([0-9\.]\+\):/\1 /')
	local new_servers=$(echo "$ntp_services" | awk '{print $1}' | sort)
	local old_servers=$(uci show ntpclient | grep "\.hostname=" | cut -f 2- -d = | sort)
	local section_name=
	if [ "$new_servers" != "$old_servers" ]; then
		# delete all current servers
		while uci -q delete ntpclient.@ntpserver[0]; do true; done
		echo "$ntp_services" | while read host port other; do
			section_name="$(uci add ntpclient ntpserver)"
			uci set "ntpclient.${section_name}.hostname=$host"
			uci set "ntpclient.${section_name}.port=$port"
		done
		msg_info "updating NTP entries"
		uci commit ntpclient
		# restart if there were servers available before
		[ -n "$old_servers" ] && control_ntpclient restart
	fi
	# make sure that ntpclient is running (in case it broke before)
	# never run it if there are no servers at all
	if [ -n "$new_servers" ] && [ -z "$(pidof ntpclient)" ]; then
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
			# keine Ausgabe der Zeitserver-Informationen
			start_ntpclient >/dev/null
			;;
		stop)
			stop_ntpclient
			;;
		restart)
			stop_ntpclient
			# keine Ausgabe der Zeitserver-Informationen
			start_ntpclient >/dev/null
			;;
		*)
			echo >&2 "ERROR: unknown action for 'control_ntpclient': $action"
			;;
	esac
}


add_banner_event() {
	local event=$1
	local timestamp=$(date)
	local line_suffix=" - $event -------"
	local line=" - $timestamp "
	local length=$((54-${#line_suffix}))
	(
		# Steht unser Text schon im Banner? Ansonsten hinzufuegen ...
		if grep -q 'clean_restart_log' /etc/banner; then
			true
		else
			echo " ----- clean this log with 'clean_restart_log' -------"
			echo " ------ restart times: (possibly by watchdog) --------"
		fi
		while [ "${#line}" -lt "$length" ]; do line="$line-"; done
		echo "$line$line_suffix"
	) >>/etc/banner
	sync
}


get_and_enable_olsrd_library_uci_prefix() {
	local new_section
	local lib_file
	local uci_prefix=
	local library=$1
	local current=$(uci show olsrd | grep -q "^olsrd\.@LoadPlugin\[[0-9]\+\]\.library=$library\.so")
	if [ -n "$current"]; then
		uci_prefix=$(echo "$current" | cut -f 1 -d = | sed 's/\.library$//')
	else
		new_section=$(uci add olsrd LoadPlugin)
		uci_prefix=olsrd.${new_section}
		lib_file=$(find /usr/lib -type f -name "${library}.*")
		if [ -z "$lib_file" ]; then
			msg_info "FATAL ERROR: Failed to find olsrd '$library' plugin. Some Opennet services will fail."
		else
			uci set "${uci_prefix}.library=$(basename "$lib_file")"
		fi
	fi
	# Plugin aktivieren; Praefix ausgeben
	if [ -n "$uci_prefix" ]; then
		# moeglicherweise vorhandenen 'ignore'-Parameter abschalten
		uci_is_true "$(uci_get "${uci_prefix}.ignore" 0)" && uci set "${uci_prefix}.ignore=0"
		echo "$uci_prefix"
	fi
	return 0
}


# Aktion fuer die initiale Policy-Routing-Initialisierung nach dem System-Boot
initialize_olsrd_policy_routing() {
	# TODO: diese Funktion sollten wir durch netzwerk-Konfigurationen (ubus?) triggern lassen

	local wait_count
	local olsr_prio
	local main_prio
	local network

	# Ermittle die Prioritaet der olsr-Regeln im Policy-Routing
	# Die Suche wird fehlschlagen, wenn olsrd nicht laeuft
	if [ -n "$(pidof olsrd)" ]; then
		wait_count=15
		while [ -z "$olsr_prio" ] && [ "$wait_count" != "0" ]; do
			olsr_prio=$(ip rule show | awk 'BEGIN{FS="[: ]"} /olsrd/ {print $1; exit}')
			sleep 1
			: $((wait_count--))
		done
	fi

	# Policy-Regel setzen, falls sie fehlen sollte
	if [ -z "$olsr_prio" ]; then
		olsr_prio=$OLSR_POLICY_DEFAULT_PRIORITY
		ip rule add table olsrd prio "$olsr_prio"
		ip rule add table olsrd-default prio "$((olsr_prio+10))"
	fi

	# "main"-Regel fuer lokale Quell-Pakete prioritisieren (opennet-Routing soll lokales Routing nicht beeinflussen)
	# "main"-Regel fuer alle anderen Pakete nach hinten schieben (weniger wichtig als olsr)
	main_prio=$(ip rule show | awk 'BEGIN{FS="[: ]"} /main/ {print $1; exit}')
	for network in $(uci_get firewall.zone_local.network); do
		networkprefix=$(get_network "$network")
		[ -n "$networkprefix" ] && ip rule add from "$networkprefix" table main prio "$main_prio"
	done
	ip rule add from all iif lo table main prio "$main_prio"
	ip rule del table main
	ip rule add table main prio "$((olsr_prio+20))"

	# Pakete fuer opennet-IP-Bereiche sollen nicht in der main-Tabelle (lokale Interfaces) behandelt werden
	# Falls spezifischere Interfaces vorhanden sind (z.B. 192.168.1.0/24), dann greift die "throw"-Regel natuerlich nicht.
	for networkprefix in $(uci_get on-core.defaults.on_network); do
		ip route prepend throw "$networkprefix" table main
	done

	# Pakete in Richtung lokaler Netzwerke (sowie "free") werden nicht von olsrd behandelt.
	# TODO: koennen wir uns darauf verlassen, dass olsrd diese Regeln erhaelt?
	for network in $(uci_get firewall.zone_local.network) $(uci_get firewall.zone_free.network); do
		networkprefix=$(get_network "$network")
		[ -z "$networkprefix" ] && continue
		ip route add throw "$networkprefix" table olsrd
		ip route add throw "$networkprefix" table olsrd-default
	done
	return 0
}


#################################################################################
# Auslesen eines Werts aus einer Key/Value-Datei
# Jede Zeile dieser Datei enthaelt einen Feldnamen und einen Wert - beide sind durch
# ein beliebiges whitespace-Zeichen getrennt.
# Wir verwenden dies beispielsweise fuer die volatilen Gateway-Zustandsdaten.
# Parameter status_file: der Name der Key/Value-Datei
# Parameter field: das Schluesselwort
_get_file_dict_value() {
	local status_file=$1
	local field=$2
	awk "{if (\$1 == \"${field}\") { printf \"%s\", \$2; exit 0; }}" "$status_file"
}

#################################################################################
# Schreiben eines Werts in eine Key-Value-Datei
# Dateiformat: siehe _get_file_dict_value
# Parameter status_file: der Name der Key/Value-Datei
# Parameter field: das Schluesselwort
# Parameter value: der neue Wert
_set_file_dict_value() {
	local status_file=$1
	local field=$2
	local new_value=$3
	# Filtere bisherige Zeilen mit dem key heraus.
	# Fuege anschliessend die Zeile mit dem neuen Wert an.
	# Die Sortierung sorgt fuer gute Vergleichbarkeit, um die Anzahl der
	# Schreibvorgaenge (=Wahrscheinlichkeit von gleichzeitigem Zugriff) zu reduzieren.
	(
		while read fieldname value; do
			[ "$field" != "$fieldname" ] && echo "$fieldname $value"
		 done <"$GATEWAY_STATUS_FILE"
		# leerer Wert -> loeschen
		[ -n "$new_value" ] && echo "$field $new_value"
	) | sort | update_file_if_changed "$GATEWAY_STATUS_FILE" || true
}


# hole einen der default-Werte der aktuellen Firmware
# Die default-Werte werden nicht von der Konfigurationsverwaltung uci verwaltet.
# Somit sind nach jedem Upgrade imer die neuesten Standard-Werte verfuegbar.
get_on_default() {
	_get_file_dict_value "$ON_DEFAULTS_FILE" "$1"
}


#################################################################################
# Auslesen einer Gateway-Information
# Parameter ip: IP-Adresse des Gateways
# Parameter key: Informationsschluessel ("age", "status", ...)
get_gateway_value() {
	_get_file_dict_value "$GATEWAY_STATUS_FILE" "${1}_${2}"
}

#################################################################################
# Aendere eine gateway-Information
# Parameter ip: IP-Adresse des Gateways
# Parameter key: Informationsschluessel ("age", "status", ...)
# Parameter value: der neue Inhalt
set_gateway_value() {
	_set_file_dict_value "$GATEWAY_STATUS_FILE" "${1}_${2}" "$3"
}

#################################################################################
# Auslesen einer Gateway-Information
# Parameter ip: IP-Adresse des Gateways
# Parameter key: Informationsschluessel ("age", "status", ...)
get_ugw_value() {
	_get_file_dict_value "$UGW_STATUS_FILE" "${1}_${2}"
}

#################################################################################
# Aendere eine gateway-Information
# Parameter ip: IP-Adresse des Gateways
# Parameter key: Informationsschluessel ("age", "status", ...)
# Parameter value: der neue Inhalt
set_ugw_value() {
	_set_file_dict_value "$UGW_STATUS_FILE" "${1}_${2}" "$3"
}

# Parse die olsr-Service-Datei
# Die Service-Datei enthaelt Zeilen streng definierter Form (durchgesetzt vom nameservice-Plugin).
# Beispielhafte Eintraege:
#   http://192.168.0.15:8080|tcp|ugw upload:3 download:490 ping:108         #192.168.2.15
#   dns://192.168.10.4:53|udp|dns                                           #192.168.10.4
# Parameter: service-Type (z.B. "gw", "ugw", "dns", "ntp"
# Ergebnis:
#   HOST:PORT DETAILS
get_services() {
	local filter_service=$1
	local url
	local proto
	local service
	local details
	local host_port
	[ -e "$SERVICES_FILE" ] || return
	# remove trailing commentary (containing the service's source IP address)
	# use "|" and space as a separator
	IFS='| '
	grep "^[^#]" "$SERVICES_FILE" | sed 's/[\t ]\+#[^#]\+//' | while read url proto service details; do
		if [ "$service" = "$filter_service" ]; then
		       host_port=$(echo "$url" | cut -f 3 -d /)
		       echo "$host_port" "$details"
		fi
	done
}

get_network() {
# 	if [ "$(uci_get network.$1.type)" == "bridge" ]; then
# 		ifname="br-$1"
# 	else
# 		ifname=$(uci_get network.$1.ifname)
# 	fi
	. "${IPKG_INSTROOT:-}/lib/functions.sh"
	include "${IPKG_INSTROOT:-}/lib/network"
	scan_interfaces
	ifname="$(config_get $1 ifname)"
	if [ -n "$ifname" ] && [ "$ifname" != "none" ]; then
		ipaddr="$(ip address show label "$ifname" | awk '/inet/ {print $2; exit}')"
		[ -z "$ipaddr" ] || { eval $(ipcalc -p -n "$ipaddr"); echo $NETWORK/$PREFIX; }
	fi
}


get_on_firmware_version() {
	opkg status on-core | awk '{if (/Version/) print $2;}'
}


update_olsr_interfaces() {
	uci set -q "olsrd.@Interface[0].interface=$(uci_get firewall.zone_opennet.network)"
	uci commit olsrd
	/etc/init.d/olsrd restart
}


# $1 is on_id, $2 is on_ipschema, $3 is no
# ACHTUNG: manche Aufrufende verlassen sich darauf, dass on_id_1 und
# on_id_2 nach dem Aufruf verfuegbar sind (also _nicht_ "local")
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

# check if a given lock file:
# A) exists, but it is outdated (determined by the number of seconds given as second parameter)
# B) exists, but is fresh
# C) does not exist
# A + C return success and create that file
# B return failure and do not touch that file
aquire_lock() {
	local lock_file=$1
	local max_age_seconds=$2
	[ ! -e "$lock_file" ] && touch "$lock_file" && return 0
	local now=$(date +%s)
	local file_timestamp=$(date --reference "$lock_file" +%s)
	[ "$((now-file_timestamp))" -gt "$max_age_seconds" ] && touch "$lock_file" && return 0
	return 1
}

# pruefe einen VPN-Verbindungsaufbau
# Parameter:
#   Gateway-IP: die announcierte IP des Gateways
#   Gateway-Name: der Name des Gateways
#   Schluesseldatei: z.B. $VPN_DIR/on_aps.key
#   Zertifikatsdatei: z.B. $VPN_DIR/on_aps.crt
#   CA-Zertifikatsdatei: z.B. $VPN_DIR/opennet-ca.crt
# Ergebnis: Exitcode=0 bei Erfolg
verify_vpn_connection() {
	local gw_ipaddr=$1
	local gw_name=$2
	local key_file=$3
	local cert_file=$4
	local ca_file=$5
	local openvpn_opts

	# if there is no ipaddr stored then query dns for IP address
	[ -z "$gw_ipaddr" ] && gw_ipaddr=$(query_dns "$gw_name")
	[ -z "$gw_ipaddr" ] && return 1
	
	# if gateway could only be reached over a local tunnel, dont use it - it will not work anyway
	[ -n "$(ip route show table $olsrd_routingTable | awk '/tap|tun/ && $1 == "'$gw_ipaddr'"')" ] && return 1
	
	msg_debug "start vpn test of $gw_ipaddr"

	# check if it is possible to open tunnel to the gateway (10 sec. maximum)
	# Assembling openvpn parameters ...
	openvpn_opts="--dev null"
	
	# some openvpn options:
	#   dev-type: excplicitly choose "tun" (the type cannot be guessed via the "null" device name)
	#   nobind: choose random local port - otherwise late packets from previous connection tests will cause errors
	#   ifconfig-noexec: we do not want to configure a device (and mess up routing tables)
	#   route-nopull: ignore any advertised routes - we do not want to redirect traffic
	openvpn_opts="$openvpn_opts --dev-type tun --client --nobind --ifconfig-noexec --route-nopull"

	# some timing options:
	#   inactive: close connection after 10s without traffic
	#   ping-exit: close connection after 5s without a ping from the other side (which is probably disabled)
	openvpn_opts="$openvpn_opts --inactive 6 retry 0 --ping-exit 2"

	# other options:
	#   verb: verbose level 3 is required for the TLS messages
	#   nice: testing is not too important
	#   resolv-retry: no need to be extra careful and patient
	openvpn_opts="$openvpn_opts --verb 3 --nice 3 --resolv-retry 0"

	# prevent a real connection (otherwise we may break our current vpn tunnel):
	#   tls-verify: force a tls handshake failure
	#   tls-exit: stop immediately after tls handshake failure
	#   ns-cert-type: enforce a connection against a server certificate (instead of peer-to-peer)
	openvpn_opts="$openvpn_opts --tls-verify /bin/false --tls-exit --ns-cert-type server"

	# check if the output contains a magic line
	openvpn $openvpn_opts --remote "$gw_ipaddr" 1600 --ca "$ca_file" --cert "$cert_file" --key "$key_file" \
		| grep -q "Initial packet" && return 0
	return 1
}

