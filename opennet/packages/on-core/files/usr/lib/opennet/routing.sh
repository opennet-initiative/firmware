# opennet-Funktionen rund um das Routing
# wird durch "on-helper" eingebunden

RT_FILE=/etc/iproute2/rt_tables
RT_START_ID=11

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


# erzeuge Policy-Rules fuer den IP-Bereich eines Netzwerkinterface
# Parameter: logisches Netzwerkinterface
# weitere Parameter: Rule-Spezifikation
add_zone_policy_rules() {
	trap "error_trap add_zone_policy_rules $*" $GUARD_TRAPS
	local zone=$1
	shift
	local network
	local networkprefix
	for network in $(get_zone_interfaces "$zone"); do
		networkprefix=$(get_network "$network")
		[ -n "$networkprefix" ] && ip rule add from "$networkprefix" "$@"
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
	local network
	local networkprefix
	local priority=$OLSR_POLICY_DEFAULT_PRIORITY

	delete_policy_rule table "$ROUTING_TABLE_MESH"
	ip rule add table "$ROUTING_TABLE_MESH" prio "$((priority++))"

	delete_policy_rule table "$ROUTING_TABLE_MESH_DEFAULT"
	ip rule add table "$ROUTING_TABLE_MESH_DEFAULT" prio "$((priority++))"

	# "main"-Regel fuer lokale Quell-Pakete prioritisieren (opennet-Routing soll lokales Routing nicht beeinflussen)
	# "main"-Regel fuer alle anderen Pakete nach hinten schieben (weniger wichtig als olsr)
	delete_policy_rule table main
	add_zone_policy_rules "$ZONE_LOCAL" table main prio "$((priority++))"
	ip rule add iif lo table main prio "$((priority++))"
	ip rule add table main prio "$((priority++))"

	# Uplinks folgen erst nach main
	delete_policy_rule table "$ROUTE_RULE_ON"
	add_zone_policy_rules "$ZONE_LOCAL" table "$ROUTE_RULE_ON" prio "$((priority++))"
	add_zone_policy_rules "$ZONE_FREE" table "$ROUTE_RULE_ON" prio "$((priority++))"
	ip rule add iif lo table "$ROUTE_RULE_ON" prio "$((priority++))"


	# Pakete fuer opennet-IP-Bereiche sollen nicht in der main-Tabelle (lokale Interfaces) behandelt werden
	# Falls spezifischere Interfaces vorhanden sind (z.B. 192.168.1.0/24), dann greift die "throw"-Regel natuerlich nicht.
	delete_throw_routes main
	for networkprefix in $(get_on_core_default on_network); do
		ip route prepend throw "$networkprefix" table main
	done

	# Pakete in Richtung lokaler Netzwerke (sowie "free") werden nicht von olsrd behandelt.
	# TODO: koennen wir uns darauf verlassen, dass olsrd diese Regeln erhaelt?
	delete_throw_routes "$ROUTING_TABLE_MESH"
	delete_throw_routes "$ROUTING_TABLE_MESH_DEFAULT"
	for network in $(get_zone_interfaces "$ZONE_LOCAL") $(get_zone_interfaces "$ZONE_FREE"); do
		networkprefix=$(get_network "$network")
		[ -z "$networkprefix" ] && continue
		ip route add throw "$networkprefix" table "$ROUTING_TABLE_MESH"
		ip route add throw "$networkprefix" table "$ROUTING_TABLE_MESH_DEFAULT"
	done
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
	# verwende den letzten gecachten Wert, falls vorhanden
	[ -z "$ROUTE_INFO" ] && ROUTE_INFO=$(echo /routes | nc localhost 2006 | grep "^[0-9]" | sed 's#/32##')
	echo "$ROUTE_INFO" | awk '{ if ($1 == "'$target'") { print $4; exit; } }'
}

