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

# Abbruch bei:
#  u = undefinierten Variablen
#  e = Fehler
set -eu

GATEWAY_STATUS_FILE=/tmp/on-openvpn_gateways.status
UGW_STATUS_FILE=/tmp/on-ugw_gateways.status
ON_CORE_DEFAULTS_FILE=/usr/share/opennet/core.defaults
ON_OPENVPN_DEFAULTS_FILE=/usr/share/opennet/openvpn.defaults
ON_USERGW_DEFAULTS_FILE=/usr/share/opennet/usergw.defaults
ON_WIFIDOG_DEFAULTS_FILE=/usr/share/opennet/wifidog.defaults
SERVICES_FILE=/var/run/services_olsr
DNSMASQ_SERVERS_FILE_DEFAULT=/var/run/dnsmasq.servers
OLSR_POLICY_DEFAULT_PRIORITY=20000
# leider, leider unterstuetzt die busybox-ash kein trap "ERR"
GUARD_TRAPS=EXIT
ROUTE_RULE_ON=on-tunnel
ZONE_LOCAL=lan
ZONE_MESH=on_mesh
ZONE_TUNNEL=on_vpn
ZONE_FREE=free
NETWORK_TUNNEL=on_vpn
NETWORK_FREE=free
ROUTING_TABLE_MESH=olsrd
ROUTING_TABLE_MESH_DEFAULT=olsrd-default

DEBUG=

# siehe Entwicklungsdokumentation (Entwicklungshinweise -> Shell-Skripte -> Fehlerbehandlung)
trap "error_trap __main__ $*" $GUARD_TRAPS


. "${IPKG_INSTROOT:-}/usr/lib/opennet/olsr.sh"
. "${IPKG_INSTROOT:-}/usr/lib/opennet/routing.sh"
. "${IPKG_INSTROOT:-}/usr/lib/opennet/uci.sh"


# Schreibe eine log-Nachricht bei fehlerhaftem Skript-Abbruch
# Uebliche Parameter sind der aktuelle Funktionsname, sowie Parameter der aufgerufenen Funktion.
# Jede nicht-triviale Funktion sollte zu Beginn folgende Zeile enthalten:
#    trap "error_trap FUNKTIONSNAME_HIER_EINTRAGEN $*" $GUARD_TRAPS
error_trap() {
	# dies ist der Exitcode des Skripts (im Falle der EXIT trap)
	local exitcode=$?
	local message="ERROR [trapped]: $*"
	[ "$exitcode" = 0 ] && exit 0
	msg_info "$message"
	echo >&2 "$message"
	exit "$exitcode"
}


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
	[ -z "$DEBUG" ] && DEBUG=$(get_on_core_default debug)
	uci_is_true "$DEBUG" && logger -t "$(basename "$0")[$$]" "$1" || true
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


# Gather the list of hosts announcing a NTP services.
# Store this list as a dnsmasq 'server-file'.
# The file is only updated in case of changes.
update_dns_servers() {
	trap "error_trap update_dns_servers $*" $GUARD_TRAPS
	local use_dns="$(uci_get on-core.services.use_olsrd_dns)"
	# return if we should not use DNS servers provided via olsrd
	uci_is_false "$use_dns" && return
	local servers_file=$(uci_get "dhcp.@dnsmasq[0].serversfile")
	if [ -z "$servers_file" ]; then
	       servers_file=$DNSMASQ_SERVERS_FILE_DEFAULT
	       uci set "dhcp.@dnsmasq[0].serversfile=$servers_file"
	       uci commit "dhcp.@dnsmasq[0]"
	       reload_config
	fi
	# replace ":" with "#" (dnsmasq expects this port separator)
	get_services dns | sed 's/^\([0-9\.]\+\):/\1#/' | sort | while read host other; do
		echo "server=$host"
	done | update_file_if_changed "$servers_file" || return 0
	# es gab eine Aenderung
	msg_info "updating DNS servers"
	killall -s HUP dnsmasq	# reload config
}

# Gather the list of hosts announcing a NTP services.
# Store this list as ntpclient-compatible uci settings.
# The uci settings are only updated in case of changes.
# ntpclient is restarted in case of changes.
update_ntp_servers() {
	trap "error_trap update_ntp_servers $*" $GUARD_TRAPS
	local use_ntp="$(uci_get on-core.services.use_olsrd_ntp)"
	# return if we should not use NTP servers provided via olsrd
	uci_is_false "$use_ntp" && return
	# schreibe die Liste der NTP-Server neu
	uci_delete system.ntp.server
	get_services ntp | sed 's/^\([0-9\.]\+\):/\1 /' | while read host port other; do
		[ -n "$port" -a "$port" != "123" ] && host="$host:$port"
		uci_add_list "system.ntp.server" "$host"
	done
	apply_changes system
}


add_banner_event() {
	trap "error_trap add_banner_event $*" $GUARD_TRAPS
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


# Lege eine Weiterleitungsregel fuer die firewall an (firewall.@forwarding[?]=...)
# WICHTIG: anschliessend muss "uci commit firewall" ausgefuehrt werden
# Parameter: Quell-Zone und Ziel-Zone
add_zone_forward() {
	local source=$1
	local dest=$2
	local section
	local uci_prefix=$(find_first_uci_section firewall forwarding "src=$source" "dest=$dest")
	# die Weiterleitungsregel existiert bereits -> Ende
	[ -n "$uci_prefix" ] && return 0
	# neue Regel erstellen
	section=$(uci add firewall forwarding)
	uci set "firewall.${section}.src=$source"
	uci set "firewall.${section}.dest=$dest"
}


# Loesche eine Weiterleitungsregel fuer die firewall (Quelle -> Ziel)
# WICHTIG: anschliessend muss "uci commit firewall" ausgefuehrt werden
# Parameter: Quell-Zone und Ziel-Zone
delete_zone_forward() {
	local source=$1
	local dest=$2
	local uci_prefix=$(find_first_uci_section firewall forwarding "src=$source" "dest=$dest")
	# die Weiterleitungsregel existiert nicht -> Ende
	[ -z "$uci_prefix" ] && return 0
	# Regel loeschen
	uci_delete "$uci_prefix"
}


# Das Masquerading in die Opennet-Zone soll nur fuer bestimmte Quell-Netze erfolgen.
# Diese Funktion wird bei hotplug-Netzwerkaenderungen ausgefuehrt.
update_opennet_zone_masquerading() {
	local network
	local networkprefix
	local uci_prefix=$(find_first_uci_section firewall zone "name=$ZONE_MESH")
	# Abbruch, falls die Zone fehlt
	[ -z "$uci_prefix" ] && msg_info "failed to find opennet mesh zone ($ZONE_MESH)" && return 0
	# masquerading aktiveren (nur fuer die obigen Quell-Adressen)
	uci set "${uci_prefix}.masq=1"
	# alle masquerade-Netzwerke entfernen
	uci_delete "${uci_prefix}.masq_src"
	# aktuelle Netzwerke wieder hinzufuegen
	for network in $(get_zone_interfaces "$ZONE_LOCAL"); do
		networkprefix=$(get_network "$network")
		uci_add_list "${uci_prefix}.masq_src" "$networkprefix"
	done
	apply_changes firewall
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
	# fehlende Datei -> kein Ergebnis
	[ -e "$status_file" ] || return 0
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
	# fehlende Datei? Leer erzeugen ...
	[ -e "$status_file" ] || touch "$status_file"
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
get_on_core_default() { _get_file_dict_value "$ON_CORE_DEFAULTS_FILE" "$1"; }
get_on_openvpn_default() { _get_file_dict_value "$ON_OPENVPN_DEFAULTS_FILE" "$1"; }
get_on_usergw_default() { _get_file_dict_value "$ON_USERGW_DEFAULTS_FILE" "$1"; }
get_on_wifidog_default() { _get_file_dict_value "$ON_WIFIDOG_DEFAULTS_FILE" "$1"; }


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
# Parameter: service-Type (z.B. "gw", "ugw", "dns", "ntp")
# Ergebnis:
#   HOST:PORT DETAILS
get_services() {
	trap "error_trap get_services $*" $GUARD_TRAPS
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
	trap "error_trap get_network $*" $GUARD_TRAPS
	local ifname=$(
		# Kurzzeitig den eventuellen strikten Modus abschalten.
		# (lib/functions.sh kommt mit dem strikten Modus nicht zurecht)
		set +eu
		. "${IPKG_INSTROOT:-}/lib/functions.sh"
		include "${IPKG_INSTROOT:-}/lib/network"
		scan_interfaces
		config_get "$1" ifname
	)
	if [ -n "$ifname" ] && [ "$ifname" != "none" ]; then
		# TODO: aktuell nur IPv4
		ipaddr="$(ip address show label "$ifname" | awk '/inet / {print $2; exit}')"
		[ -z "$ipaddr" ] || { eval $(ipcalc -p -n "$ipaddr"); echo $NETWORK/$PREFIX; }
	fi
}


get_on_firmware_version() {
	opkg status on-core | awk '{if (/Version/) print $2;}'
}


# Parameter:
#   on_id: die ID des AP - z.B. "1.96" oder "2.54"
#   on_ipschema: siehe "get_on_core_default on_ipschema"
#   interface_number: 0..X
# ACHTUNG: manche Aufrufende verlassen sich darauf, dass on_id_1 und
# on_id_2 nach dem Aufruf verfuegbar sind (also _nicht_ "local")
get_on_ip() {
	local on_id=$1
	local on_ipschema=$2
	local no=$3
	echo "$on_id" | grep -q "\." || on_id=1.$on_id
	on_id_1=$(echo "$on_id" | cut -d . -f 1)
	on_id_2=$(echo "$on_id" | cut -d . -f 2)
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


clean_stale_pid_file() {
	local pidfile=$1
	local pid
	[ -e "$pidfile" ] | return 0
	pid=$(cat "$pidfile" | sed 's/[^0-9]//g')
	[ -z "$pid" ] && msg_debug "removing broken PID file: $pidfile" && rm "$pidfile" && return 0
	[ ! -e "/proc/$pid" ] && msg_debug "removing stale PID file: $pidfile" && rm "$pidfile" && return 0
	return 0
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
	trap "error_trap verify_vpn_connection $*" $GUARD_TRAPS
	local gw_ipaddr=$1
	local gw_name=$2
	local key_file=$3
	local cert_file=$4
	local ca_file=$5
	local openvpn_opts

	# if there is no ipaddr stored then query dns for IP address
	[ -z "$gw_ipaddr" ] && gw_ipaddr=$(query_dns "$gw_name")
	[ -z "$gw_ipaddr" ] && trap "" $GUARD_TRAPS && return 1
	
	# if gateway could only be reached over a local tunnel, dont use it - it will not work anyway
	[ -n "$(ip route show table $olsrd_routingTable | awk '/tap|tun/ && $1 == "'$gw_ipaddr'"')" ] && trap "" $GUARD_TRAPS && return 1
	
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
	trap "" $GUARD_TRAPS && return 1
}


# jeder AP bekommt einen Bereich von zehn Ports fuer die Port-Weiterleitung zugeteilt
# Parameter (optional): common name des Nutzer-Zertifikats
get_port_forwards() {
	local client_cn=${1:-}
	[ -z "$client_cn" ] && client_cn=$(get_client_cn)
	local port_count=10
	local cn_address=
	local portbase
	local targetports

	[ -z "$client_cn" ] && msg_debug "$(basename "$0"): failed to get Common Name - maybe there is no certificate?" && return 0

	if echo "$client_cn" | grep -q '^\(\(1\.\)\?[0-9][0-9]\?[0-9]\?\.aps\.on\)$'; then
		portbase=10000
		cn_address=${client_cn%.aps.on}
		cn_address=${cn_address#*.}
	elif echo "$client_cn" | grep -q '^\([0-9][0-9]\?[0-9]\?\.mobile\.on\)$'; then
		portbase=12550
		cn_address=${client_cn%.mobile.on}
	elif echo "$client_cn" | grep -q '^\(2[\._-][0-9][0-9]\?[0-9]\?\.aps\.on\)$'; then
		portbase=15100
		cn_address=${client_cn%.aps.on}
		cn_address=${cn_address#*.}
	elif echo "$client_cn" | grep -q '^\(3[\._-][0-9][0-9]\?[0-9]\?\.aps\.on\)$'; then
		portbase=20200
		cn_address=${client_cn%.aps.on}
		cn_address=${cn_address#*.}
	fi

	if [ -z "$cn_address" ] || [ "$cn_address" -lt 1 ] || [ "$cn_address" -gt 255 ]; then
		msg_info "$(basename "$0"): invalidate certificate Common Name ($client_cn)"
		return 1
	fi

	targetports=$((portbase + (cn_address-1)*port_count))
	echo "$client_cn $targetports $((targetports+9))"
}


# ermittle das Alter (vergangene Sekunden seit der letzten Aenderung) einer Datei
get_file_age_seconds() {
	local filename=$1
	[ -e "$filename" ] || return 1
	local filestamp=$(date --reference "$filename" +%s)
	local now=$(date +%s)
	echo $((now - filestamp))
	return 0
}


get_zone_interfaces() {
	local zone=$1
	local uci_prefix=$(find_first_uci_section firewall zone "name=$zone")
	# keine Zone -> keine Interfaces
	[ -z "$uci_prefix" ] && return 0
	uci_get "${uci_prefix}.network"
	return 0
}


add_interface_to_zone() {
	local zone=$1
	local interface=$2
	local uci_prefix=$(find_first_uci_section firewall zone "name=$zone")
	[ -z "$uci_prefix" ] && msg_debug "failed to add interface '$interface' to non-existing zone '$zone'" && return 1
	uci_add_list "${uci_prefix}.network" "$interface"
}


del_interface_from_zone() {
	local zone=$1
	local interface=$2
	local uci_prefix=$(find_first_uci_section firewall zone "name=$zone")
	[ -z "$uci_prefix" ] && msg_debug "failed to remove interface '$interface' from non-existing zone '$zone'" && return 1
	uci_del_list "${uci_prefix}.network" "$interface"
}


apply_changes() {
	local config=$1
	# keine Aenderungen
	[ -z "$(uci changes "$config")" ] && return 0
	uci commit "$config"
	case "$config" in
		system|network|firewall)
			reload_config || true
			;;
		olsrd)
			/etc/init.d/olsrd restart || true
			;;
		openvpn)
			/etc/init.d/openvpn reload || true
			;;
		*)
			msg_info "no handler defined for applying config changes for '$config'"
			;;
	esac
	return 0
}


get_zone_of_interface() {
	local interface=$1
	local prefix
	local networks
	local zone
	uci show firewall | grep "^firewall\.@zone\[[0-9]\+\]\.network=" | sed 's/=/ /' | while read prefix networks; do
	zone=$(uci_get "${prefix%.network}.name")
		echo " $networks " | grep -q "[ \t]$interface[ \t]" && echo "$zone" && return 0
	done
	return 1
}


# Liefere die sortierte Liste der Opennet-Interfaces.
# Prioritaeten:
# 1. dem Netzwerk ist ein Geraet zugeordnet
# 2. Netzwerkname beginnend mit "on_wifi", "on_eth", ...
# 3. alphabetische Sortierung der Netzwerknamen
get_sorted_opennet_interfaces() {
	local uci_prefix
	local order
	# wir vergeben einfach statische Ordnungsnummern:
	#   10 - nicht konfigurierte Interfaces
	#   20 - konfigurierte Interfaces
	# Offsets basierend auf dem Netzwerknamen:
	#   1 - on_wifi*
	#   2 - on_eth*
	#   3 - alle anderen
	for network in $(get_zone_interfaces "$ZONE_MESH"); do
		uci_prefix=network.$network
		order=20
		[ "$(uci_get "${uci_prefix}.ifname")" == "none" ] && order=10
		if [ "${network#on_wifi}" != "$network" ]; then
			order=$((order+1))
		elif [ "${network#on_eth}" != "$network" ]; then
			order=$((order+2))
		else
			order=$((order+3))
		fi
		echo "$order $network"
	done | sort -n | cut -f 2 -d " "
}


# Setzen einer Opennet-ID.
# 1) Hostnamen setzen
# 2) IPs fuer alle Opennet-Interfaces setzen
# 3) Main-IP in der olsr-Konfiguration setzen
# 4) IP des Interface "free" setzen
# 5) DHCP-Redirect fuer wifidog setzen
set_opennet_id() {
	local new_id=$1
	local network
	local uci_prefix
	local ipaddr
	local main_ipaddr
	local free_ipaddr
	local ipschema
	local netmask
	local if_counter=0
	# ID normalisieren (AP7 -> AP1.7)
	echo "$new_id" | grep -q "\." || new_id=1.$new_id
	# ON_ID in on-core-Settings setzen
	prepare_on_uci_settings
	uci set "on-core.settings.on_id=$new_id"
	# Hostnamen konfigurieren
	find_all_uci_sections system system | while read uci_prefix; do
		uci set "${uci_prefix}.hostname=AP-$(echo "$new_id" | tr . -)"
	done
	apply_changes system
	# IP-Adressen konfigurieren
	ipschema=$(get_on_core_default on_ipschema)
	netmask=$(get_on_core_default on_netmask)
	main_ipaddr=$(get_on_ip "$new_id" "$ipschema" 0)
	for network in $(get_sorted_opennet_interfaces); do
		uci_prefix=network.$network
		[ "$(uci_get "${uci_prefix}.proto")" != "static" ] && continue
		ipaddr=$(get_on_ip "$new_id" "$ipschema" "$if_counter")
		uci set "${uci_prefix}.ipaddr=$ipaddr"
		uci set "${uci_prefix}.netmask=$netmask"
		: $((if_counter++))
	done
	# OLSR-MainIP konfigurieren
	olsr_set_main_ip "$main_ipaddr"
	apply_changes olsrd
	# wifidog-Interface konfigurieren
	ipschema=$(get_on_wifidog_default free_ipschema)
	netmask=$(get_on_wifidog_default free_netmask)
	free_ipaddr=$(get_on_ip "$new_id" "$ipschema" 0)
	uci_prefix=network.$NETWORK_FREE
	uci set "${uci_prefix}.proto=static"
	uci set "${uci_prefix}.ipaddr=$free_ipaddr"
	uci set "${uci_prefix}.netmask=$netmask"
	apply_changes network
	# DHCP-Forwards fuer wifidog
	# Ziel ist beispielsweise folgendes Setup:
	#   firewall.@redirect[0]=redirect
	#   firewall.@redirect[0].src=opennet
	#   firewall.@redirect[0].proto=udp
	#   firewall.@redirect[0].src_dport=67
	#   firewall.@redirect[0].target=DNAT
	#   firewall.@redirect[0].src_port=67
	#   firewall.@redirect[0].dest_ip=10.3.1.210
	#   firewall.@redirect[0].src_dip=192.168.1.210
	find_all_uci_sections firewall redirect "src=$ZONE_MESH" proto=udp src_dport=67 src_port=67 target=DNAT | while read uci_prefix; do
		uci set "${uci_prefix}.name=DHCP-Forward Opennet"
		uci set "${uci_prefix}.dest_ip=$free_ipaddr"
		uci set "${uci_prefix}.src_dip=$main_ipaddr"
	done
	apply_changes firewall
}


# Ermittle den aktuell definierten UGW-Portforward.
# Ergebnis (tab-separiert fuer leichte 'cut'-Behandlung des Output):
#   lokale IP-Adresse fuer UGW-Forward
#   externer Gateway
# TODO: siehe auch http://dev.on-i.de/ticket/49 - wir duerfen uns nicht auf die iptables-Ausgabe verlassen
get_ugw_portforward() {
	local chain=zone_${ZONE_MESH}_prerouting
	# TODO: vielleicht lieber den uci-Portforward mit einem Namen versehen?
	iptables -L "$chain" -t nat -n | awk 'BEGIN{FS="[ :]+"} /udp dpt:1600 to:/ {printf $3 "\t" $5 "\t" $10; exit}'
}

