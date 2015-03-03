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
DEFAULT_RULE_PRIO_OFFSET=100
OLSR_ROUTE_CACHE_FILE=/tmp/olsr_routes.cache


## @fn is_ipv4()
## @brief Prüfe ob der übergebene Text eine IPv4-Adresse ist
## @param target eine Zeichenkette (wahrscheinlich ein DNS-Name, eine IPv4- oder IPv6-Adresse)
is_ipv4() {
	local target="$1"
	echo "$target" | grep -q -E "^[0-9]+(\.[0-9]+){3}$"
}


## @fn is_ipv6()
## @brief Prüfe ob der übergebene Text eine IPv6-Adresse ist
## @param target eine Zeichenkette (wahrscheinlich ein DNS-Name, eine IPv4- oder IPv6-Adresse)
## @details Achtung: der Test ist recht oberflächlich und kann falsche Positive liefern.
is_ipv6() {
	local target="$1"
	echo "$target" | grep -q "^[0-9a-fA-F:]\+$"
}


## @fn filter_routable_addresses()
## @brief Filtere aus einer Menge von Ziel-IPs diejenigen heraus, für die eine passende Routing-Regel existiert.
## @details Lies IP-Addressen zeilenweise via stdin ein und gib alle Adressen aus, die (laut "ip route get") erreichbar sind.
##   Dies bedeutet nicht, dass wir mit den Adressen kommunizieren koennen - es geht lediglich um lokale Routing-Regeln.
## @return zeilenweise Ausgabe der route-baren Ziel-IPs:w
filter_routable_addresses() {
	local ip
	while read ip; do
		[ -n "$(get_target_route_interface "$ip")" ] && echo "$ip" || true
	done
	return 0
}


## @fn get_target_route_interface()
## @brief Ermittle das Netzwerkinterface, über den der Verkehr zu einem Ziel laufen würde.
## @param target Hostname oder IP des Ziel-Hosts
## @details Falls erforderlich, findet eine Namensauflösung statt.
## @return Name des physischen Netzwerk-Interface, über den der Verkehr zum Ziel-Host fließen würde
get_target_route_interface() {
	local target=$1
	local ipaddr
	if is_ipv4 "$target" || is_ipv6 "$target"; then
		echo "$target"
	else
		query_dns "$target"
	fi | while read ipaddr; do
		# "failed_policy" wird von ipv6 fuer nicht-zustellbare Adressen zurueckgeliefert
		# Falls ein Hostname mehrere IP-Adressen ergibt (z.B. ipv4 und ipv6), dann werden beide geprüft.
		# Die Ergebnis der Interface-Ermittlung für eine IPv6-Adresse bei fehlendem IPv6-Gateway sieht folgendermaßen aus:
		#    root@AP-1-193:/tmp/log/on-services# ip route get 2a01:4f8:140:1222::1:7
		#    12 2a01:4f8:140:1222::1:7 from :: dev lo  src fe80::26a4:3cff:fefd:7649  metric -1  error -1
		# Wir ignorieren also Zeilen, die auf "error -1" enden.
		# Fehlermeldungen (ip: RTNETLINK answers: Network is unreachable) werden ebenfalls ignoriert.
		ip route get "$ipaddr" 2>/dev/null | grep -v ^failed_policy | grep -v "error -1$" | grep " dev " | sed 's/^.* dev \+\([^ \t]\+\) \+.*$/\1/'
	done | tail -1
}


# Entferne alle Policy-Routing-Regeln die dem gegebenen Ausdruck entsprechen.
# Es erfolgt keine Fehlerausgabe und keine Fehlermeldungen.
delete_policy_rule() {
	while ip rule del "$@"; do true; done 2>/dev/null
}


# Entferne alle throw-Regeln aus einer Tabelle
# Parameter: Tabelle
delete_throw_routes() {
	local table=$1
	ip route show table "$table" | grep "^throw " | while read throw pattern; do
		ip route del table "$table" $pattern
	done
}


# erzeuge Policy-Rules entsprechend der IP-Bereiche eines Netzwerks
# Parameter: logisches Netzwerkinterface
# weitere Parameter: Rule-Spezifikation
add_network_policy_rule_by_destination() {
	trap "error_trap add_network_policy_rule_by_destination '$*'" $GUARD_TRAPS
	local network="$1"
	shift
	local networkprefix
	for networkprefix in $(get_address_of_network "$network"); do
		[ -n "$networkprefix" ] && ip rule add to "$networkprefix" "$@" || true
	done
	return 0
}


## @fn add_zone_policy_rules_by_iif()
## @brief Erzeuge Policy-Rules fuer Quell-Interfaces
## @param zone Pakete aus allen Interfaces dieser Zone kommend sollen betroffen sein
## @param route Spezifikation einer Route (siehe 'ip route add ...')
add_zone_policy_rules_by_iif() {
	trap "error_trap add_zone_policy_rules '$*'" $GUARD_TRAPS
	local zone=$1
	shift
	local device
	for device in $(get_zone_devices "$zone"); do
		[ -n "$device" ] && ip rule add iif "$device" "$@" || true
	done
	return 0
}


## @fn initialize_olsrd_policy_routing()
## @brief Policy-Routing-Initialisierung nach dem System-Boot und nach Interface-Hotplug-Ereignissen
## @details Folgende Seiteneffekte treten ein:
##   * alle throw-Routen aus den Tabellen olsrd/olsrd-default/main werden gelöscht
##   * alle Policy-Rules mit Bezug zu den Tabellen olsrd/olsrd-default/main werden gelöscht
##   * die neuen Policy-Rules für die obigen Tabellen werden an anderer Stelle erzeugt
##   Kurz gesagt: alle bisherigen Policy-Rules sind hinterher kaputt
initialize_olsrd_policy_routing() {
	trap "error_trap initialize_olsrd_policy_routing '$*'" $GUARD_TRAPS
	local iface
	local current
	local table
	local priority=$OLSR_POLICY_DEFAULT_PRIORITY

	# Sicherstellen, dass die Tabellen existieren und zur olsrd-Konfiguration passen
	olsr_sync_routing_tables
	# die Uplink-Tabelle ist unabhaengig von olsr
	[ -z "$(get_routing_table_id "$ROUTING_TABLE_ON_UPLINK")" ] && add_routing_table "$ROUTING_TABLE_ON_UPLINK" >/dev/null

	# alle Eintraege loeschen
	delete_policy_rule table "$ROUTING_TABLE_MESH"
	delete_policy_rule table "$ROUTING_TABLE_MESH_DEFAULT"
	delete_policy_rule table "$ROUTING_TABLE_ON_UPLINK"
	delete_policy_rule table main
	delete_policy_rule table default

	# free-Verkehr geht immer in den Tunnel
	add_zone_policy_rules_by_iif "$ZONE_FREE" table "$ROUTING_TABLE_ON_UPLINK" prio "$((priority++))"

	# sehr wichtig - also zuerst: keine vorbeifliegenden Mesh-Pakete umlenken
	add_zone_policy_rules_by_iif "$ZONE_MESH" table "$ROUTING_TABLE_MESH" prio "$((priority++))"
	add_zone_policy_rules_by_iif "$ZONE_MESH" table "$ROUTING_TABLE_MESH_DEFAULT" prio "$((priority++))"

	# Pakete mit passendem Ziel orientieren sich an der main-Tabelle
	# Alle Ziele ausserhalb der mesh-Zone sind geeignet (z.B. local, free, ...).
	# Wir wollen dadurch explizit keine potentielle default-Route verwenden.
	# Aufgrund der "while"-Sub-Shell (mit separatem Variablenraum) belassen wir die Regeln
	# einfach bei gleicher Prioritaet und erhoehen diese erst anschliessend.
	get_all_network_interfaces | while read iface; do
		is_interface_in_zone "$iface" "$ZONE_MESH" && continue
		add_network_policy_rule_by_destination "$iface" table main prio "$priority"
	done
	: $((priority++))

	# alle nicht-mesh-Quellen routen auch ins olsr-Netz
	#TODO: wir sollten nur private Ziel-IP-Bereiche (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16) zulassen
	# spaeter sind konfigurierbar weitere IPs (fuer HNAs oeffentlicher Dienste) moeglich
	ip rule add table "$ROUTING_TABLE_MESH" prio "$((priority++))"
	ip rule add table "$ROUTING_TABLE_MESH_DEFAULT" prio "$((priority++))"

	# Routen, die nicht den lokalen Netz-Interfaces entsprechen (z.B. default-Routen)
	ip rule add table main prio "$((priority++))"

	# die default-Table und VPN-Tunnel fungieren fuer alle anderen Pakete als default-GW
	ip rule add table default prio "$((priority++))"
	ip rule add table "$ROUTING_TABLE_ON_UPLINK" prio "$((priority++))"
}


# Stelle sicher, dass eine sinnvolle routing-Tabellen-Datei existiert.
# Dies ist erforderlich, da kein echtes "ip"-Paket installiert ist (im busybox-Paket ist die Datei nicht enthalten).
_prepare_routing_table_file() {
	[ -e "$RT_FILE" ] && return 0
	mkdir "$(dirname "$RT_FILE")"
	cat >"$RT_FILE" << EOF
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
	grep "^[0-9]\+[ \t]\+$table_name$" "$RT_FILE" | awk '{print $1}'
	return 0
}


## @fn add_routing_table()
## @brief Erstelle einen neuen Routing-Tabellen-Eintrag.
## @param table_name der Name der zu erstellenden Routing-Tabelle
## @details Die Routing-Tabellen-Nummer wird automatisch ermittelt.
##    Sollte die Tabelle bereits existieren, dann wird ihre Nummer zurückgeliefert.
## @return die neue Routing-Tabellen-Nummer wird zurückgeliefert
add_routing_table() {
	trap "error_trap add_routing_table '$*'" $GUARD_TRAPS
	local table_name="$1"
	_prepare_routing_table_file
	local table_id=$(get_routing_table_id "$table_name")
	# schon vorhanden?
	[ -n "$table_id" ] && echo "$table_id" && return 0
	# wir muessen den Eintrag hinzufuegen
	table_id="$RT_START_ID"
	while [ -n "$(_get_file_dict_value "$RT_FILE" "$table_id")" ]; do
		: $((table_id++))
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
	# kein Ergebnis, falls noch kein Routen-Cache vorliegt (minuetlicher cronjob)
	[ ! -e "$OLSR_ROUTE_CACHE_FILE" ] && return 0
	awk '{ if ($1 == "'$target'") { print $3, $4; exit; } }' <"$OLSR_ROUTE_CACHE_FILE"
}


# Diese Funktion sollte oft (minuetlich?) aufgerufen werden, um die olsrd-Routing-Informationen abzufragen.
# Dies ist noetig, um deadlocks bei parallelem Zugriff auf den single-thread olsrd zu verhindern.
# Symptome eines deadlocks: olsrd ist beendet; viele parallele nc-Instanzen; eine davon ist an den txtinfo-Port gebunden.
update_olsr_route_cache() {
	trap "error_trap update_olsr_route_cache '$*'" $GUARD_TRAPS
	# die temporaere Datei soll verhindern, dass es zwischendurch ein Zeitfenster mit unvollstaendigen Informationen gibt
	local tmpfile="${OLSR_ROUTE_CACHE_FILE}.new"
	# Bei der Ausfuehrung via cron wird SIGPIPE eventuell behandelt, auf dass die Ausfuehrung
	# ohne Erzeugung der Datei abbrechen koennte. Daher ist die &&-Verknuepfung sinnvoll.
	request_olsrd_txtinfo routes | grep "^[0-9]" | sed 's#/32##' > "$tmpfile" && mv "$tmpfile" "$OLSR_ROUTE_CACHE_FILE"
	return 0
}

# Ende der Doku-Gruppe
## @}
