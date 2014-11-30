# opennet-Funktionen rund um das Routing
# wird durch "on-helper" eingebunden

ROUTING_TABLE_ON_UPLINK=on-tunnel
ROUTING_TABLE_MESH=olsrd
ROUTING_TABLE_MESH_DEFAULT=olsrd-default
OLSR_POLICY_DEFAULT_PRIORITY=20000
RT_FILE=/etc/iproute2/rt_tables
RT_START_ID=11
# Prioritaets-Offset fuer default-Routing-Tabellen (z.B. "default" und "olsrd-default")
DEFAULT_RULE_PRIO_OFFSET=100

# hier speichern wir die Routing-Informationen zwischenzeitlich
# Dabei gehen wir davon aus, dass dieser Prozess nicht lange laeuft, da
# die Werte nur ein einziges Mal pro Programmstart eingelesen werden.
ROUTE_INFO=


# Pruefe ob der uebegebene Text eine IPv4-Adresse ist
is_ipv4() {
	echo "$target" | grep -q -E "^[0-9]+(\.[0-9]+){3}$"
}


# Pruefe ob der uebegebene Text eine IPv6-Adresse ist
# Achtung: der Test ist recht oberflaechlich und kann falsche Positive liefern.
is_ipv6() {
	echo "$target" | grep -q "^[0-9a-fA-F:]\+$"
}


# Lies IP-Addressen via stdin ein und gib alle Adressen aus, die (laut "ip route get") erreichbar sind.
# Dies bedeutet nicht, dass wir mit den Adressen kommunizieren koennen - es geht lediglich um lokale Routing-Regeln.
filter_routable_addresses() {
	while read ip; do
		[ -n "$(get_target_route_interface "$ip")" ] && echo "$ip"
	done
	return 0
}


# Ermittle das Netzwerkinterface, ueber den der Verkehr zu einem Ziel laufen wuerde.
# Falls erforderlich, findet eine Namensaufloesung statt.
get_target_route_interface() {
	local target=$1
	local ipaddr
	if is_ipv4 "$target" || is_ipv6 "$target"; then
		ipaddr=$target
	else
		ipaddr=$(query_dns "$target")
	fi
	# "failed_policy" wird von ipv6 fuer nicht-zustellbare Adressen zurueckgeliefert
	# falls ein Hostname mehrere IP-Adressen ergibt (z.B. ipv4 und ipv6), dann werden beide probiert
	for item in $ipaddr; do
		ip route get "$item" | grep -v ^failed_policy | grep " dev " | sed 's/^.* dev \+\([^ \t]\+\) \+.*$/\1/'
	done | head -1
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
	trap "error_trap add_network_policy_rule_by_destination $*" $GUARD_TRAPS
	local network="$1"
	shift
	local networkprefix
	for networkprefix in $(get_network "$network"); do 
		[ -n "$networkprefix" ] && ip rule add to "$networkprefix" "$@" || true
	done
	return 0
}


# erzeuge Policy-Rules fuer Quell-Interfaces
# Parameter: Zone
# weitere Parameter: Rule-Spezifikation
add_zone_policy_rules_by_iif() {
	trap "error_trap add_zone_policy_rules $*" $GUARD_TRAPS
	local zone=$1
	shift
	local device
	for device in $(get_zone_devices "$zone"); do
		[ -n "$device" ] && ip rule add iif "$device" "$@" || true
	done
	return 0
}


# Aktion fuer die initiale Policy-Routing-Initialisierung nach dem System-Boot
# Folgende Seiteneffekte treten ein:
#  * alle throw-Routen aus den Tabellen olsrd/olsrd-default/main werden geloescht
#  * alle Policy-Rules mit Bezug zu den Tabellen olsrd/olsrd-default/main werden geloescht
#  * die neuen Policy-Rules fuer die obigen Tabellen werden an anderer Stelle erzeugt
# Kurz gesagt: alle bisherigen Policy-Rules sind hinterher kaputt
initialize_olsrd_policy_routing() {
	trap "error_trap initialize_olsrd_policy_routing $*" $GUARD_TRAPS
	local iface
	local current
	local table
	local priority=$OLSR_POLICY_DEFAULT_PRIORITY

	# Tabellen anmelden (nur einmalig notwendig)
	for table in "$ROUTING_TABLE_MESH" "$ROUTING_TABLE_MESH_DEFAULT" \
			"$ROUTING_TABLE_ON_UPLINK"; do
		get_or_add_routing_table "$table" >/dev/null
	done

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


# Ermitteln der table-ID einer gegebenen Policy-Routing-Tabelle.
# Falls die Tabelle nicht existiert, wird sie angelegt.
get_or_add_routing_table() {
	local table=$1
	local table_id=$(grep "^[0-9]\+[ \t]\+$table$" "$RT_FILE" | awk '{print $1}')
	# schon vorhanden?
	[ -n "$table_id" ] && echo "$table_id" && return 0
	# wir muessen den Eintrag hinzufuegen
	table_id=$RT_START_ID
	while grep -q "^$table_id[ \t]" "$RT_FILE"; do
		: $((table_id++))
	done
	echo "$table_id      $table" >> "$RT_FILE"
	echo "$table_id"
}


get_routing_distance() {
	local target="$1"
	_get_olsr_route_info_column "$target" 4
}


get_hop_count() {
	local target="$1"
	_get_olsr_route_info_column "$target" 3
}

_get_olsr_route_info_column() {
	local target="$1"
	local column="$2"
	# verwende den letzten gecachten Wert, falls vorhanden
	[ -z "$ROUTE_INFO" ] && ROUTE_INFO=$(echo /routes | nc localhost 2006 | grep "^[0-9]" | sed 's#/32##')
	echo "$ROUTE_INFO" | awk '{ if ($1 == "'$target'") { print $'$column'; exit; } }'
}

