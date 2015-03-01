## @defgroup olsr OLSR
## @brief Konfiguration und Abfrage des OLSR-Diensts. Einlesen von Diensten announciert via olsrd-nameservice.
# Beginn der Doku-Gruppe
## @{

OLSR_NAMESERVICE_SERVICE_TRIGGER=/usr/sbin/on_nameservice_trigger
SERVICES_FILE=/var/run/services_olsr
OLSR_SERVICE_UPDATE_MARKER=/var/run/waiting_for_olsr_services_update
OLSR_HTTP_PORT=8080
NETCAT_BIN=$( (which ncat nc; echo nc) | head -1)


# uebertrage die Netzwerke, die derzeit der Zone "opennet" zugeordnet sind, in die olsr-Konfiguration
# Anschliessend wird olsr und die firewall neugestartet.
# Dieses Skript sollte via hotplug bei Aenderungen der Netzwerkkonfiguration ausgefuehrt werden.
update_olsr_interfaces() {
	trap "error_trap update_olsr_interfaces '$*'" $GUARD_TRAPS
	uci set -q "olsrd.@Interface[0].interface=$(get_zone_interfaces "$ZONE_MESH")"
	apply_changes olsrd
}


# Pruefe das angegebene olsrd-Plugin aktiv ist und aktiviere es, falls dies nicht der Fall sein sollte.
# Das Ergebnis ist die uci-Sektion (z.B. "olsrd.@LoadPlugin[1]") als String.
get_and_enable_olsrd_library_uci_prefix() {
	trap "error_trap get_and_enable_olsrd_library_uci_prefix '$*'" $GUARD_TRAPS
	local new_section
	local lib_file
	local uci_prefix=
	local library=olsrd_$1
	local current=$(uci show olsrd | grep "^olsrd\.@LoadPlugin\[[0-9]\+\]\.library=$library\.so")
	if [ -n "$current" ]; then
		uci_prefix=$(echo "$current" | cut -f 1 -d = | sed 's/\.library$//')
	else
		lib_file=$(find /usr/lib -type f -name "${library}.*")
		if [ -z "$lib_file" ]; then
			msg_info "FATAL ERROR: Failed to find olsrd '$library' plugin. Some Opennet services will fail."
			trap "" $GUARD_TRAPS && return 1
		fi
		new_section=$(uci add olsrd LoadPlugin)
		uci_prefix=olsrd.${new_section}
		uci set "${uci_prefix}.library=$(basename "$lib_file")"
	fi
	# Plugin aktivieren; Praefix ausgeben
	if [ -n "$uci_prefix" ]; then
		# moeglicherweise vorhandenen 'ignore'-Parameter abschalten
		uci_is_true "$(uci_get "${uci_prefix}.ignore" 0)" && uci set "${uci_prefix}.ignore=0"
		echo "$uci_prefix"
	fi
	return 0
}


enable_ondataservice() {
	trap "error_trap enable_ondataservice '$*'" $GUARD_TRAPS
	local uci_prefix

	# schon vorhanden? Unberuehrt lassen ...
	[ -n "$(uci show olsrd | grep ondataservice)" ] && return

	# add and activate ondataservice plugin
	uci_prefix=$(get_and_enable_olsrd_library_uci_prefix "ondataservice_light")
	uci set "${uci_prefix}.interval=10800"
	uci set "${uci_prefix}.inc_interval=5"
	uci set "${uci_prefix}.database=/tmp/database.json"
}


enable_nameservice() {
	trap "error_trap enable_nameservice '$*'" $GUARD_TRAPS
	local current_trigger
	local uci_prefix

	# fuer NTP, DNS und die Gateway-Auswahl benoetigen wir das nameservice-Plugin
	local uci_prefix=$(get_and_enable_olsrd_library_uci_prefix "nameservice")
	if [ -z "$uci_prefix" ]; then
	       msg_info "Failed to find olsrd_nameservice plugin"
	else
		# Option 'services-change-script' setzen
		current_trigger=$(uci_get "${uci_prefix}.services_change_script" || true)
		[ -n "$current_trigger" ] && [ "$current_trigger" != "$OLSR_NAMESERVICE_SERVICE_TRIGGER" ] && \
			msg_info "WARNING: overwriting 'services-change-script' option of olsrd nameservice plugin with custom value. You should place a script below /etc/olsrd/nameservice.d/ instead."
		uci set "${uci_prefix}.services_change_script=$OLSR_NAMESERVICE_SERVICE_TRIGGER"
	fi
}


# Setze die Einstellung MainIP in der olsr-Konfiguration:
# Quelle 1: der erste Parameter
# Quelle 2: on-core.settings.on_id
# Quelle 3: die vorkonfigurierte Standard-IP
# Anschliessend ist "apply_changes olsrd" erforderlich.
olsr_set_main_ip() {
	trap "error_trap olsr_set_main_ip '$*'" $GUARD_TRAPS
	# Auslesen der aktuellen, bzw. der Standard-IP
	local main_ip
	if [ $# -eq 1 ]; then
		main_ip=$1
	else
		main_ip=$(get_main_ip)
	fi

	# die Main-IP ist die erste IP dieses Geraets
	uci set "olsrd.@olsrd[0].MainIp=$main_ip"
}


# Ermittle welche olsr-Module konfiguriert sind, ohne dass die Library vorhanden ist.
# Deaktiviere diese Module - fuer ein sauberes boot-Log.
disable_missing_olsr_modules() {
	trap "error_trap disable_missing_olsr_modules '$*'" $GUARD_TRAPS
	local libpath=/usr/lib
	local libline
	local libfile
	local uci_prefix
	local ignore
	uci show olsrd | grep "^olsrd.@LoadPlugin\[[0-9]\+\].library=" | while read libline; do
		uci_prefix=$(echo "$libline" | cut -f 1,2 -d .)
		libfile=$(echo "$libline" | cut -f 2- -d =)
		ignore=$(uci_get "${uci_prefix}.ignore")
		[ -n "$ignore" ] && uci_is_true "$ignore" && continue
		if [ ! -e "$libpath/$libfile" ]; then
			msg_info "Disabling missing olsr module '$libfile'"
			uci set "${uci_prefix}.ignore=1"
		fi
	done
	apply_changes olsrd
}


## @fn olsr_sync_routing_tables()
## @brief Synchronisiere die olsrd-Routingtabellen-Konfiguration mit den iproute-Routingtabellennummern.
## @details Im Konfliktfall wird die olsrd-Konfiguration an die iproute-Konfiguration angepasst.
olsr_sync_routing_tables() {
	trap "error_trap olsr_sync_routing_tables '$*'" $GUARD_TRAPS
	local olsr_name
	local iproute_name
	local olsr_id
	local iproute_id
	while read olsr_name iproute_name; do
		olsr_id=$(uci_get "olsrd.@olsrd[0].$olsr_name")
		iproute_id=$(get_routing_table_id "$iproute_name")
		# beide sind gesetzt und identisch? Alles ok ...
		[ -n "$olsr_id" -a "$olsr_id" = "$iproute_id" ] && continue
		# eventuell Tabelle erzeugen, falls sie noch nicht existiert
		[ -z "$iproute_id" ] && iproute_id=$(add_routing_table "$iproute_name")
		# olsr passt sich im Zweifel der iproute-Nummer an
		[ "$olsr_id" != "$iproute_id" ] && uci set "olsrd.@olsrd[0].$olsr_name=$iproute_id" || true
	done << EOF
RtTable		$ROUTING_TABLE_MESH
RtTableDefault	$ROUTING_TABLE_MESH_DEFAULT
EOF
	apply_changes olsrd
}


# Einlesen eines olsrd-Nameservice-Service.
# Details zum Eingabe- und Ausgabeformat: siehe "get_olsr_services".
parse_olsr_service_definitions() {
	trap "error_trap parse_olsr_service_definitions '$*'" $GUARD_TRAPS
	local url
	local proto
	local service
	local details
	local scheme
	local host
	local port
	local path
	# verwende "|" und Leerzeichen als Separatoren
	IFS='| '
	while read url proto service details; do
		scheme=$(echo "$url" | cut -f 1 -d :)
		host=$(echo "$url" | cut -f 3 -d / | cut -f 1 -d :)
		port=$(echo "$url" | cut -f 3 -d / | cut -f 2 -d :)
		path=/$(echo "$url" | cut -f 4- -d /)
		# Firmware-Versionen bis v0.4-5 veroeffentlichten folgendes Format:
		#    http://192.168.0.40:8080|tcp|ugw upload:50 download:15300 ping:23
		[ "$scheme" = "http" -a "$port" = "8080" -a "$proto" = "tcp" ] && \
			[ "$service" = "gw" -o "$service" = "ugw" ] && scheme=openvpn && port=1600 && proto=udp
		echo -e "$scheme\t$host\t$port\t$path\t$proto\t$service\t$details"
	done
}


# Parse die olsr-Service-Datei
# Die Service-Datei enthaelt Zeilen streng definierter Form (durchgesetzt vom nameservice-Plugin).
# Beispielhafte Eintraege:
#   http://192.168.0.15:8080|tcp|ugw upload:3 download:490 ping:108         #192.168.2.15
#   dns://192.168.10.4:53|udp|dns                                           #192.168.10.4
# Parameter: service-Type (z.B. "gw", "ugw", "dns", "ntp")
# Ergebnis (tab-separiert):
#   SCHEME IP PORT PATH PROTO SERVICE DETAILS
# Im Fall von "http://192.168.0.15:8080|tcp|ugw upload:3 download:490 ping:108" entspricht dies:
#   http   192.168.0.15   8080   tcp   ugw   upload:3 download:490 ping:108
get_olsr_services() {
	trap "error_trap get_olsr_services '$*'" $GUARD_TRAPS
	local filter_service
	local url
	local proto
	local service
	local details
	local scheme
	local host
	local port
	local path
	[ ! -e "$SERVICES_FILE" ] && msg_debug "no olsr-services file found: $SERVICES_FILE" && return 0
	# remove trailing commentary (containing the service's source IP address)
	grep "^[^#]" "$SERVICES_FILE" | \
		sed 's/[\t ]\+#[^#]\+//' | \
		parse_olsr_service_definitions | \
		# filtere die Ergebnisse nach einem Service-Typ, falls selbiger als erster Parameter angegeben wurde
		if [ "$#" -ge 1 ]; then awk "{ if (\$6 == \"$1\") print \$0; }"; else cat -; fi
	return 0
}


update_olsr_services() {
	trap "error_trap update_olsr_services '$*'" $GUARD_TRAPS
	local scheme
	local ip
	local port
	local path
	local proto
	local service
	local details
	local timestamp
	local service_name
	local min_timestamp=$(($(get_time_minute) - $(get_on_core_default "service_expire_minutes")))
	# aktuell verbreitete Dienste benachrichtigen
	get_olsr_services | while read scheme ip port path proto service details; do
		notify_service "$service" "$scheme" "$ip" "$port" "$proto" "$path" "$details" "olsr"
	done
	# veraltete Dienste entfernen
	get_services | filter_services_by_value "source=olsr" | while read service_name; do
		timestamp=$(get_service_value "$service_name" "timestamp" 0)
		# der Service ist zu lange nicht aktualisiert worden
		[ "$timestamp" -lt "$min_timestamp" ] && delete_service "$service_name" || true
	done
	# aktualisiere DNS- und NTP-Dienste
	apply_changes on-core
}


schedule_olsrd_service_update() {
	touch "$OLSR_SERVICE_UPDATE_MARKER"
}


run_scheduled_olsrd_service_updates() {
	[ -e "$OLSR_SERVICE_UPDATE_MARKER" ] || return 0
	# zuerst loeschen - sonst verpassen wir eventuell ein Ereignis
	rm -f "$OLSR_SERVICE_UPDATE_MARKER"
	update_olsr_services
}


## @fn request_olsrd_txtinfo()
## @brief Sende eine Anfrage an das txtinfo-Interface von olsrd
## @details Über die Standardeingabe können Anfragen (z.B.: '/hna') übergeben werden.
##   Das Resultat ist auf der Standardausgabe verfügbar.
##   Bei Problemen mit dem Verbindungsaufbau erscheint ein Hinweis im syslog.
request_olsrd_txtinfo() {
	"$NETCAT_BIN" -w 2 localhost 2006 2>/dev/null || msg_info "get_olsrd_txtinfo: olsrd is not running"
}

# Ende der Doku-Gruppe
## @}
