## @defgroup routing Routing
## @brief Abfrage von Routing-Informationen und Einrichtung des Policy-Routings.
# Beginn der Doku-Gruppe
## @{

ROUTING_TABLE_ON_UPLINK=on-tunnel
ROUTING_TABLE_MESH=olsrd
ROUTING_TABLE_MESH_DEFAULT=olsrd-default
OLSR_POLICY_DEFAULT_PRIORITY=20000
RT_FILE=/etc/iproute2/rt_tables
RT_START_ID=11
# Prioritaets-Offset fuer default-Routing-Tabellen (z.B. "default" und "olsrd-default")
# shellcheck disable=SC2034
DEFAULT_RULE_PRIO_OFFSET=100
OLSR_ROUTE_CACHE_FILE=/tmp/olsr_routes.cache


## @fn is_ipv4()
## @brief Prüfe ob der übergebene Text eine IPv4-Adresse ist
## @param target eine Zeichenkette (wahrscheinlich ein DNS-Name, eine IPv4- oder IPv6-Adresse)
## @details Die IP-Adresse darf mit einem Netzwerkpraefix enden.
is_ipv4() {
	local target="$1"
	echo "$target" | grep -q -E '^[0-9]+(\.[0-9]+){3}(/[0-9]+)?$'
}


## @fn is_ipv6()
## @brief Prüfe ob der übergebene Text eine IPv6-Adresse ist
## @param target eine Zeichenkette (wahrscheinlich ein DNS-Name, eine IPv4- oder IPv6-Adresse)
## @details Achtung: der Test ist recht oberflächlich und kann falsche Positive liefern.
is_ipv6() {
	local target="$1"
	echo "$target" | grep -q -E "^[0-9a-fA-F:]+(/[0-9]+)?$"
}


## @fn filter_routable_addresses()
## @brief Filtere aus einer Menge von Ziel-IPs diejenigen heraus, für die eine passende Routing-Regel existiert.
## @details Lies IP-Addressen zeilenweise via stdin ein und gib alle Adressen aus, die (laut "ip route get") erreichbar sind.
##   Dies bedeutet nicht, dass wir mit den Adressen kommunizieren koennen - es geht lediglich um lokale Routing-Regeln.
## @return zeilenweise Ausgabe der route-baren Ziel-IPs:w
filter_routable_addresses() {
	local ip
	while read -r ip; do
		[ -z "$(get_target_route_interface "$ip")" ] || echo "$ip"
	done
	return 0
}


## @fn get_target_route_interface()
## @brief Ermittle das Netzwerkinterface, über den der Verkehr zu einem Ziel laufen würde.
## @param target Hostname oder IP des Ziel-Hosts
## @details Falls erforderlich, findet eine Namensauflösung statt.
## @return Name des physischen Netzwerk-Interface, über den der Verkehr zum Ziel-Host fließen würde
get_target_route_interface() {
	local target="$1"
	local all_addresses
	local ipaddr
	local route_get_args=
	if is_ipv4 "$target" || is_ipv6 "$target"; then
		all_addresses=$target
	else
		all_addresses=$(query_dns "$target")
	fi
	for ipaddr in $all_addresses; do
		# "failed_policy" wird von ipv6 fuer nicht-zustellbare Adressen zurueckgeliefert
		# Falls ein Hostname mehrere IP-Adressen ergibt (z.B. ipv4 und ipv6), dann werden beide geprüft.
		# Die Ergebnis der Interface-Ermittlung für eine IPv6-Adresse bei fehlendem IPv6-Gateway sieht folgendermaßen aus:
		#    root@AP-1-193:/tmp/log/on-services# ip route get 2a01:4f8:140:1222::1:7
		#    12 2a01:4f8:140:1222::1:7 from :: dev lo  src fe80::26a4:3cff:fefd:7649  metric -1  error -1
		# oder:
		#    root@AP-2-156:~# ip route get 2001:67c:1400:2430::1
		#    prohibit 2001:67c:1400:2430::1 from :: dev lo  table unspec  proto kernel  src fe80::216:3eff:fe34:2aa5  metric 4294967295  error -13
		# Wir ignorieren also Zeilen, die auf "error -1" oder "error -13" enden.
		# Fehlermeldungen (ip: RTNETLINK answers: Network is unreachable) werden ebenfalls ignoriert.
		# shellcheck disable=SC2086
		ip route get "$ipaddr" $route_get_args 2>/dev/null \
			| grep -vE "^(failed_policy|prohibit)" \
			| grep -vE "error -(1|13)$" \
			| grep " dev " \
			| sed 's/^.* dev \+\([^ \t]\+\) \+.*$/\1/'
	done | tail -1
}


# Entferne alle Policy-Routing-Regeln die dem gegebenen Ausdruck entsprechen.
# Es erfolgt keine Fehlerausgabe und keine Fehlermeldungen.
delete_policy_rule() {
	local family="$1"
	shift
	while ip -family "$family" rule del "$@"; do true; done 2>/dev/null
}


## @fn add_network_policy_rule_by_destination()
## @brief erzeuge Policy-Rules entsprechend der IP-Bereiche eines Netzwerks
## @param network logisches Netzwerkinterface
## @param more weitere Parameter: Policy-Rule-Spezifikation
add_network_policy_rule_by_destination() {
	trap 'error_trap add_network_policy_rule_by_destination "$*"' EXIT
	local family="$1"
	local network="$2"
	shift 2
	local network_with_prefix
	for network_with_prefix in $(get_current_addresses_of_network "$network"); do
		is_ipv4 "$network_with_prefix" && [ "$family" != "inet" ] && continue
		is_ipv6 "$network_with_prefix" && [ "$family" != "inet6" ] && continue
		ip -family "$family" rule add to "$network_with_prefix" "$@" || true
	done
	return 0
}


## @fn add_zone_policy_rules_by_iif()
## @brief Erzeuge Policy-Rules fuer Quell-Interfaces
## @param family "inet" oder "inet6"
## @param zone Pakete aus allen Interfaces dieser Zone kommend sollen betroffen sein
## @param route Spezifikation einer Route (siehe 'ip route add ...')
add_zone_policy_rules_by_iif() {
	trap 'error_trap add_zone_policy_rules "$*"' EXIT
	local family="$1"
	local zone="$2"
	shift 2
	local interface
	local device
	# ermittle alle physischen Geräte inklusive Bridge-Interfaces, die zu dieser Zone gehören
	for interface in $(get_zone_log_interfaces "$zone"); do
		get_device_of_interface "$interface"
		for device in $(get_subdevices_of_interface "$interface"); do
			echo "$device"
		done
	done | sort | uniq | while read -r device; do
		[ -n "$device" ] && [ "$device" != "none" ] && ip -family "$family" rule add iif "$device" "$@"
		true
	done
	return 0
}


## @fn initialize_olsrd_policy_routing()
## @brief Policy-Routing-Initialisierung nach dem System-Boot und nach Interface-Hotplug-Ereignissen
## @details Folgende Seiteneffekte treten ein:
##   * alle Policy-Rules mit Bezug zu den Tabellen olsrd/olsrd-default/main werden gelöscht
##   * die neuen Policy-Rules für die obigen Tabellen werden an anderer Stelle erzeugt
##   Kurz gesagt: alle bisherigen Policy-Rules sind hinterher kaputt
initialize_olsrd_policy_routing() {
	trap 'error_trap initialize_olsrd_policy_routing "$*"' EXIT
	local iface
	local priority="$OLSR_POLICY_DEFAULT_PRIORITY"

	# Sicherstellen, dass die Tabellen existieren und zur olsrd-Konfiguration passen
	olsr_sync_routing_tables
	# die Uplink-Tabelle ist unabhaengig von olsr
	add_routing_table "$ROUTING_TABLE_ON_UPLINK" >/dev/null

	# alle Eintraege loeschen
	delete_policy_rule inet table "$ROUTING_TABLE_MESH"
	delete_policy_rule inet table "$ROUTING_TABLE_MESH_DEFAULT"
	delete_policy_rule inet table "$ROUTING_TABLE_ON_UPLINK"
	delete_policy_rule inet table main
	delete_policy_rule inet table default

	# free-Verkehr geht immer in den Tunnel (falls das Paket installiert ist)
	if [ -n "${ZONE_FREE:-}" ]; then
		add_zone_policy_rules_by_iif inet "$ZONE_FREE" table "$ROUTING_TABLE_ON_UPLINK" prio "$priority"
		priority=$((priority + 1))
	fi

	# sehr wichtig - also zuerst: keine vorbeifliegenden Mesh-Pakete umlenken
	add_zone_policy_rules_by_iif inet "$ZONE_MESH" table "$ROUTING_TABLE_MESH" prio "$priority"
	priority=$((priority + 1))
	add_zone_policy_rules_by_iif inet "$ZONE_MESH" table "$ROUTING_TABLE_MESH_DEFAULT" prio "$priority"
	priority=$((priority + 1))

	# Pakete mit passendem Ziel orientieren sich an der main-Tabelle
	# Alle Ziele ausserhalb der mesh-Zone sind geeignet (z.B. local, free, ...).
	# Wir wollen dadurch explizit keine potentielle default-Route verwenden.
	# Aufgrund der "while"-Sub-Shell (mit separatem Variablenraum) belassen wir die Regeln
	# einfach bei gleicher Prioritaet und erhoehen diese erst anschliessend.
	for iface in $(get_all_network_interfaces); do
		is_interface_in_zone "$iface" "$ZONE_MESH" && continue
		add_network_policy_rule_by_destination inet "$iface" table main prio "$priority"
	done
	priority=$((priority + 1))

	# alle nicht-mesh-Quellen routen auch ins olsr-Netz
	#TODO: wir sollten nur private Ziel-IP-Bereiche (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16) zulassen
	# spaeter sind konfigurierbar weitere IPs (fuer HNAs oeffentlicher Dienste) moeglich
	ip rule add table "$ROUTING_TABLE_MESH" prio "$priority"
	priority=$((priority + 1))
	ip rule add table "$ROUTING_TABLE_MESH_DEFAULT" prio "$priority"
	priority=$((priority + 1))

	# Routen, die nicht den lokalen Netz-Interfaces entsprechen (z.B. default-Routen)
	ip rule add table main prio "$priority"
	priority=$((priority + 1))

	# die default-Table und VPN-Tunnel fungieren fuer alle anderen Pakete als default-GW
	ip rule add table default prio "$priority"
	priority=$((priority + 1))
	ip rule add table "$ROUTING_TABLE_ON_UPLINK" prio "$priority"
	priority=$((priority + 1))
}


# Stelle sicher, dass eine sinnvolle routing-Tabellen-Datei existiert.
# Dies ist erforderlich, falls kein echtes "ip"-Paket installiert ist (im busybox-Paket ist die Datei nicht enthalten).
_prepare_routing_table_file() {
	[ -e "$RT_FILE" ] && return 0
	mkdir -p "$(dirname "$RT_FILE")"
	cat >"$RT_FILE" << EOF
# erzeugt von "on-core"
#
255	local
254	main
253	default
0	unspec
#
# local
#
#1	inr.ruhep
EOF
}


## @fn get_routing_table_id()
## @brief Ermittle die Nummer der namentlich gegebenen Routing-Tabelle.
## @param table_name Name der gesuchten Routing-Tabelle
## @return Routing-Tabellen-ID oder nichts (falls die Tabelle nicht existiert)
get_routing_table_id() {
	local table_name="$1"
	_prepare_routing_table_file
	# Tabellennummer ausgeben, falls sie vorhanden ist
	grep '^[0-9]\+[ \t]\+'"$table_name$" "$RT_FILE" | awk '{print $1}'
	return 0
}


## @fn add_routing_table()
## @brief Erstelle einen neuen Routing-Tabellen-Eintrag.
## @param table_name der Name der zu erstellenden Routing-Tabelle
## @details Die Routing-Tabellen-Nummer wird automatisch ermittelt.
##    Sollte die Tabelle bereits existieren, dann wird ihre Nummer zurückgeliefert.
## @return die neue Routing-Tabellen-Nummer wird zurückgeliefert
add_routing_table() {
	trap 'error_trap add_routing_table "$*"' EXIT
	local table_name="$1"
	_prepare_routing_table_file
	local table_id
	table_id=$(get_routing_table_id "$table_name")
	# schon vorhanden?
	[ -n "$table_id" ] && echo "$table_id" && return 0
	# wir muessen den Eintrag hinzufuegen
	table_id="$RT_START_ID"
	while [ -n "$(_get_file_dict_value "$table_id" "$RT_FILE")" ]; do
		table_id=$((table_id + 1))
	done
	echo "$table_id      $table_name" >> "$RT_FILE"
	echo "$table_id"
}


## @fn get_hop_count_and_etx()
## @brief Liefere den Hop-Count und den ETX-Wert für einen Zielhost zurück.
## @param host die Ziel-IP
## @returns Der Hop-Count und der ETX-Wert wird mit einem Leerzeichen separiert ausgegeben. Falls keine Route bekannt ist, ist das Ergebnis ein leerer String.
## @details Die Quelle dieser Information ist olsrd. Routen außerhalb von olsrd werden nicht beachtet.
get_hop_count_and_etx() {
	local target="$1"
	local result
	# kein Ergebnis, falls noch kein Routen-Cache vorliegt (minuetlicher cronjob)
	[ ! -e "$OLSR_ROUTE_CACHE_FILE" ] && return 0
	result=$(awk '{ if ($1 == "'"$target"'") { print $3, $4; exit; } }' <"$OLSR_ROUTE_CACHE_FILE")
	[ -n "$result" ] && echo "$result" && return 0
	# Überprüfe, ob die IP des Zielhost die eigene IP ist. Dann sollte distance=0 gesetzt werden.
	if is_ipv4 "$target" || is_ipv6 "$target"; then
		result=$(ip route get "$target" 2>/dev/null | grep -w "dev lo" || true)
		[ -n "$result" ] && echo "$result" | grep -vq "^unreachable" && echo "0 0" && return 0
		true
	fi
	# Hole Daten von OLSR2
	if is_ipv6 "$target" && is_function_available "request_olsrd2_txtinfo"; then
		request_olsrd2_txtinfo "olsrv2info" "route" \
			| awk '{ if ($1 == "'"$target"'") { cost=$(NF-1); hops=$NF; print(hops, 1 / cost) }}'
	fi
}


## @fn get_traceroute()
## @brief Liefere einen traceroute zu einem Host zurueck.
## @param host der Ziel-IP
## @return Eine mit Komma getrennte Liste von IPs
get_traceroute() {
	local target="$1"
	local result
	
	# wenn kein Parameter uebergeben, dann breche ab
	[ -z "$target" ] && return 0
	
	# Verarbeitung:
	#  - erste Zeile auslassen (traceroute-Header)
	#  - unbekannte Hops ignorieren ("*" oder "???")
	#  - Einträge durch Kommata separieren
	#  - unterdrücke Fehler (z.B. keine Route zum Host)
	timeout 20 traceroute -w 1 -q 1 -n "$target" 2>/dev/null | awk '
		{ if ((NR > 1) && ($2 != "*") && ($2 != "???") && $2) {
			if (NR == 2) {
				printf($2);
			} else {
				printf(",%s", $2);
			}
		}}'
}


# Diese Funktion sollte oft (minuetlich?) aufgerufen werden, um die olsrd-Routing-Informationen abzufragen.
# Dies ist noetig, um deadlocks bei parallelem Zugriff auf den single-thread olsrd zu verhindern.
# Symptome eines deadlocks: olsrd ist beendet; viele parallele nc-Instanzen; eine davon ist an den txtinfo-Port gebunden.
update_olsr_route_cache() {
	trap 'error_trap update_olsr_route_cache "$*"' EXIT
	# die temporaere Datei soll verhindern, dass es zwischendurch ein Zeitfenster mit unvollstaendigen Informationen gibt
	local tmpfile="${OLSR_ROUTE_CACHE_FILE}.new"
	# Bei der Ausfuehrung via cron wird SIGPIPE eventuell behandelt, auf dass die Ausfuehrung
	# ohne Erzeugung der Datei abbrechen koennte. Daher ist die &&-Verknuepfung sinnvoll.
	request_olsrd_txtinfo rou | sed '/^[^0-9]/d; s#/32##' > "$tmpfile" && mv "$tmpfile" "$OLSR_ROUTE_CACHE_FILE"
	return 0
}


## @fn get_olsr_route_count_by_device()
## @brief Liefere die Anzahl von olsr-Routen, die auf ein bestimmtes Netzwerk-Interface verweisen
get_olsr_route_count_by_device() {
	local device_regex="$1"
	# kein Ergebnis, falls noch kein Routen-Cache vorliegt (minuetlicher cronjob)
	[ -e "$OLSR_ROUTE_CACHE_FILE" ] || return 0
	awk '{ print $5 }' "$OLSR_ROUTE_CACHE_FILE" | grep -c "^$device_regex$" || true
}


## @fn get_olsr_route_count_by_neighbour()
## @brief Liefere die Anzahl von olsr-Routen, die auf einen bestimmten Routing-Nachbarn verweisen.
get_olsr_route_count_by_neighbour() {
	local neighbour_ip="$1"
	# kein Ergebnis, falls noch kein Routen-Cache vorliegt (minuetlicher cronjob)
	[ -e "$OLSR_ROUTE_CACHE_FILE" ] || return 0
	awk 'BEGIN { count=0; } { if ($2 == "'"$neighbour_ip"'") count++; } END { print count; }' "$OLSR_ROUTE_CACHE_FILE"
}


## @fn get_olsr_neighbours()
## @brief Ermittle die direkten olsr-Nachbarn und liefere ihre IPs und interessante Kennzahlen zurück.
## details Ergebnisformat: NEIGHBOUR_IP LINK_QUALITY NEIGHBOUR_LINK_QUALITY ETX ROUTE_COUNT
get_olsr_neighbours() {
	local local_ip
	local neighbour_ip
	local lq
	local nlq
	local etx
	local ip_interface_map
	local interface_description
	ip_interface_map=$(request_olsrd_txtinfo "int" | awk '{print($5, $1);}')
	request_olsrd_txtinfo "lin" | grep "^[0-9]" | awk '{ print $1,$2,$4,$5,$6 }' | sort -n \
			| while read -r local_ip neighbour_ip lq nlq etx; do
		# there may be one or more interfaces (e.g. multiple TAP tunnels for UGW APs)
		interface_description=$(echo "$ip_interface_map" | grep -wF "$local_ip" | awk '{print $2}' | tr '\n' '/' | sed 's#/$##')
		[ -z "$interface_description" ] && interface_description="unknown"
		echo "$neighbour_ip $interface_description $lq $nlq $etx $(get_olsr_route_count_by_neighbour "$neighbour_ip")"
	done
}

# Ende der Doku-Gruppe
## @}
