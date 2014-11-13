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

# fuer Entwicklungszwecke: uebermaessig ausfuehrliche Ausgabe aktivieren
[ "${ON_DEBUG:-}" = "1" ] && set -x


GATEWAY_STATUS_FILE=/tmp/on-openvpn_gateways.status
ON_CORE_DEFAULTS_FILE=/usr/share/opennet/core.defaults
ON_OPENVPN_DEFAULTS_FILE=/usr/share/opennet/openvpn.defaults
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
VPN_DIR_TEST=/etc/openvpn/opennet_vpntest
OPENVPN_CONFIG_BASEDIR=/var/etc/openvpn

DEBUG=${DEBUG:-}

# siehe Entwicklungsdokumentation (Entwicklungshinweise -> Shell-Skripte -> Fehlerbehandlung)
trap "error_trap __main__ $*" $GUARD_TRAPS


# Module laden
for fname in olsr.sh routing.sh uci.sh services.sh on-usergw.sh; do
	fname=${IPKG_INSTROOT:-}/usr/lib/opennet/$fname
	[ -e "$fname" ] && . "$fname"
done


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
# Liefere alle IPs fuer diesen Namen zurueck
query_dns() {
	nslookup "$1" | sed '1,/^Name:/d' | awk '{print $3}' | sort -n
}


query_dns_reverse() { nslookup "$1" 2>/dev/null | tail -n 1 | awk '{ printf "%s", $4 }'; }

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
	local host
	local port
	local use_dns="$(uci_get on-core.settings.use_olsrd_dns)"
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
	get_olsr_services dns | cut -f 2,3 | sort | while read host port; do
		echo "server=$host#$port"
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
	local host
	local port
	local use_ntp="$(uci_get on-core.settings.use_olsrd_ntp)"
	# return if we should not use NTP servers provided via olsrd
	uci_is_false "$use_ntp" && return
	# schreibe die Liste der NTP-Server neu
	uci_delete system.ntp.server
	get_olsr_services ntp | cut -f 2,3 | while read host port; do
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
	local key
	local value
	# fehlende Datei -> kein Ergebnis
	[ -e "$status_file" ] || return 0
	while read key value; do
		[ "$field" = "$key" ] && echo -n "$value" && return
	done < "$status_file"
	return 0
}


# Liefere alle Schluessel aus einer Key/Value-Datei, die mit dem mitgelieferten "keystart"
# beginnen.
_get_file_dict_keys() {
	local status_file=$1
	local keystart=$2
	local key
	local value
	# fehlende Datei -> kein Ergebnis
	[ -e "$status_file" ] || return 0
	while read key value; do
		[ "${key#$keystart}" != "$key" ] && echo "${key#$keystart}"
	done < "$status_file"
	return 0
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
	local fieldname
	local value
	# fehlende Datei? Leer erzeugen ...
	[ -e "$status_file" ] || touch "$status_file"
	# Filtere bisherige Zeilen mit dem key heraus.
	# Fuege anschliessend die Zeile mit dem neuen Wert an.
	# Die Sortierung sorgt fuer gute Vergleichbarkeit, um die Anzahl der
	# Schreibvorgaenge (=Wahrscheinlichkeit von gleichzeitigem Zugriff) zu reduzieren.
	(
		while read fieldname value; do
			[ "$field" != "$fieldname" ] && echo "$fieldname $value"
		 done <"$status_file"
		# leerer Wert -> loeschen
		[ -n "$new_value" ] && echo "$field $new_value"
	) | sort | update_file_if_changed "$status_file" || true
}


# hole einen der default-Werte der aktuellen Firmware
# Die default-Werte werden nicht von der Konfigurationsverwaltung uci verwaltet.
# Somit sind nach jedem Upgrade imer die neuesten Standard-Werte verfuegbar.
get_on_core_default() { _get_file_dict_value "$ON_CORE_DEFAULTS_FILE" "$1"; }
get_on_openvpn_default() { _get_file_dict_value "$ON_OPENVPN_DEFAULTS_FILE" "$1"; }
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


# Liefere die aktuell konfigurierte Main-IP zurueck
get_main_ip() {
	local on_id=$(uci_get on-core.settings.on_id "$(get_on_core_default on_id_preset)")
	local ipschema=$(get_on_core_default on_ipschema)
	get_on_ip "$on_id" "$ipschema" 0
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
	[ -e "$pidfile" ] || return 0
	pid=$(cat "$pidfile" | sed 's/[^0-9]//g')
	[ -z "$pid" ] && msg_debug "removing broken PID file: $pidfile" && rm "$pidfile" && return 0
	[ ! -e "/proc/$pid" ] && msg_debug "removing stale PID file: $pidfile" && rm "$pidfile" && return 0
	return 0
}


# pruefe einen VPN-Verbindungsaufbau
# Parameter:
#   openvpn-Konfigurationsdatei
# optionale zusaetzliche Parameter:
#   Schluesseldatei: z.B. $VPN_DIR/on_aps.key
#   Zertifikatsdatei: z.B. $VPN_DIR/on_aps.crt
#   CA-Zertifikatsdatei: z.B. $VPN_DIR/opennet-ca.crt
# Ergebnis: Exitcode=0 bei Erfolg
verify_vpn_connection() {
	trap "error_trap verify_vpn_connection $*" $GUARD_TRAPS
	local config_file=$1
	local key_file=${2:-}
	local cert_file=${3:-}
	local ca_file=${4:-}
	local wan_dev
	local openvpn_opts
	local hostname
	local status_output

	msg_debug "start vpn test of <$config_file>"

	# check if it is possible to open tunnel to the gateway (10 sec. maximum)
	# Assembling openvpn parameters ...
	openvpn_opts="--dev null"
	
	# some openvpn options:
	#   ifconfig-noexec: we do not want to configure a device (and mess up routing tables)
	#   route-nopull: ignore any advertised routes - we do not want to redirect traffic
	openvpn_opts="$openvpn_opts --ifconfig-noexec --route-nopull"

	# some timing options:
	#   inactive: close connection after 10s without traffic
	#   ping-exit: close connection after 5s without a ping from the other side (which is probably disabled)
	openvpn_opts="$openvpn_opts --inactive 6 retry 2 --ping-exit 2"

	# other options:
	#   verb: verbose level 3 is required for the TLS messages
	#   nice: testing is not too important
	#   resolv-retry: fuer ipv4/ipv6-Tests sollten wir mehrere Versuche zulassen
	openvpn_opts="$openvpn_opts --verb 3 --nice 3 --resolv-retry 3"

	# prevent a real connection (otherwise we may break our current vpn tunnel):
	#   tls-verify: force a tls handshake failure
	#   tls-exit: stop immediately after tls handshake failure
	#   ns-cert-type: enforce a connection against a server certificate (instead of peer-to-peer)
	openvpn_opts="$openvpn_opts --tls-verify /bin/false --tls-exit --ns-cert-type server"

	[ -n "$key_file" ] && openvpn_opts="$openvpn_opts --key \"$key_file\""
	[ -n "$cert_file" ] && openvpn_opts="$openvpn_opts --cert \"$cert_file\""
	[ -n "$ca_file" ] && openvpn_opts="$openvpn_opts --ca \"$ca_file\""

	# check if the output contains a magic line
	status_output=$(openvpn --config "$config_file" $openvpn_opts || true)
	echo "$status_output" | grep -q "Initial packet" && return 0
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


is_interface_in_zone() {
	local in_interface=$1
	local zone=$2
	for log_interface in $(get_zone_interfaces "$2"); do
		for phys_interface in $(uci_get "network.${log_interface}.ifname"); do
			# Entferne den Teil nach Doppelpunkten - fuer Alias-Interfaces
			[ "$in_interface" = "$(echo "$phys_interface" | cut -f 1 -d :)" ] && return 0
		done
	done
	return 1
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
	uci del_list "${uci_prefix}.network=$interface"
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
		on-usergw)
			update_openvpn_ugw_settings
			apply_changes openvpn
			apply_changes olsrd
			apply_changes firewall
			;;
		on-core)
			# nichts zu tun
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
	#   10 - konfigurierte Interfaces
	#   20 - nicht konfigurierte Interfaces
	# Offsets basierend auf dem Netzwerknamen:
	#   1 - on_wifi*
	#   2 - on_eth*
	#   3 - alle anderen
	for network in $(get_zone_interfaces "$ZONE_MESH"); do
		uci_prefix=network.$network
		order=10
		[ "$(uci_get "${uci_prefix}.ifname")" == "none" ] && order=20
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
	apply_changes on-core
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


# Durchsuche eine Schluessel-Wert-Liste nach einem Schluessel und liefere den dazugehoerigen Wert zurueck.
# Beispiel:
#   foo=bar baz=nux
# Der Separator ist konfigurierbar - standardmaessig wird das Gleichheitszeichen verwendet.
# Die Liste wird auf der Standardeingabe erwartet.
# Der erste und einzige Parameter ist der gewuenschte Schluessel.
get_from_key_value_list() {
	local search_key=$1
	local separator=${2:-=}
	local key_value
	local key
	sed 's/[ \t]\+/\n/g' | while read key_value; do
		key=$(echo "$key_value" | cut -f 1 -d "$separator")
		[ "$key" = "$search_key" ] && echo "$key_value" | cut -f 2- -d "$separator" && break
	done
	return 0
}


# Pruefe ob die angegebene Openvpn-Konfiguration auf ein Zertifikat verweist, das nicht existiert.
# Falls der Ort der Zertifikatsdatei nicht zweifelsfrei ermittelt werden kann, dann liefert die
# Funktion "wahr" zurueck.
# Parameter: Name der Openvpn-Konfiguration (uci show openvpn.*)
openvpn_has_certificate() {
	local uci_prefix="openvpn.$1"
	local cert_file
	local config_file=$(uci_get "${uci_prefix}.config")
	if [ -n "$config_file" ]; then
		# Verweis auf lokale config-Datei (keine uci-basierte Konfiguration)
		if [ -e "$config_file" ]; then
			cert_file=$(grep "^cert[ \t]" "$config_file" | while read key value; do echo "$value"; done)
		else
			# im Zweifelsfall: unklar
			cert_file=
		fi
	else
		# Konfiguration liegt in uci
		cert_file=$(uci_get "${uci_prefix}.cert")
	fi
	# das Zertifikat scheint irgendwie anders konfiguriert zu sein - im Zeifelsfall: OK
	[ -z "$cert_file" ] && return 0
	# existiert die Datei?
	[ ! -e "$cert_file" ] && return 1
	return 0
}


# Wandle einen uebergebenene Parameter in eine Zeichenkette um, die sicher als Dateiname verwendet werden kann
get_safe_filename() {
	echo "$1" | sed 's/[^a-zA-Z0-9._\-]/_/g'
}


# Schreibe eine openvpn-Konfigurationsdatei.
# Parameter: ein uci-Praefix unterhalb von "on-openvpn" (on-openvpn.@gateway[x]) oder "on-usergw" (on-usergw.\@uplink[x]
# Parameter: uci-Konfiguration (on-openvpn oder on-usergw)
# Parameter: uci-Liste (z.B. "server" oder "uplink")
rebuild_openvpn_config() {
	local config_name="$1"
	local config_domain="$2"
	local config_branch="$3"
	local uci_prefix=$(find_first_uci_section "$config_domain" "$config_branch" "name=$config_name")
	local hostname=$(uci_get "${uci_prefix}.hostname")
	local port=$(uci_get "${uci_prefix}.port")
	local protocol=$(uci_get "${uci_prefix}.protocol")
	[ "$protocol" = "tcp" ] && protocol=tcp-client
	local template=$(uci_get "${uci_prefix}.template")
	local config_file=$(uci_get "${uci_prefix}.config_file")
	# Konfigurationsdatei neu schreiben
	mkdir -p "$(dirname "$config_file")"
	(
		echo "remote $(uci_get "${uci_prefix}.hostname") $port"
		echo "proto $protocol"
		echo "writepid /var/run/${config_name}.pid"
		cat "$template"
	) >"$config_file"
}


update_one_openvpn_setup() {
	local config_name="$1"
	local uci_domain="$2"
	local uci_branch="$3"
	local uci_prefix=$(find_first_uci_section "$uci_domain" "$uci_branch" "name=$config_name")
	local config_file=$(uci_get "${uci_prefix}.config_file")
	rebuild_openvpn_config "$config_name" "$uci_domain" "$uci_branch"
	# uci-Konfiguration setzen
	# das Attribut "enable" belassen wir unveraendert
	uci set "openvpn.${config_name}=openvpn"
	uci set "openvpn.${config_name}.config=$config_file"
	apply_changes openvpn
}


# Pruefe alle openvpn-Konfigurationen fuer MIG- oder UGW-Verbindungen.
# Quelle: on-openvpn.@server[x] oder on-usergw.@uplink[x]
# Ziel: openvpn.on_mig_* oder openvpn.on_ugw_*
update_openvpn_settings() {
	local uci_domain="$1"
	local uci_branch="$2"
	find_all_uci_sections on-usergw uplink type=openvpn | while read uci_prefix; do
		update_one_openvpn_setup "$(uci_get "${uci_prefix}.name")" "$uci_domain" "$uci_branch"
	done
}

