## @defgroup services Dienste
## @brief Verwaltung von Diensten (z.B. via olsrd-nameservice announciert)
# Beginn der Doku-Gruppe
## @{

VOLATILE_SERVICE_STATUS_DIR=/tmp/on-services-volatile.d
PERSISTENT_SERVICE_STATUS_DIR=/etc/on-services.d
# eine grosse Zahl sorgt dafuer, dass neu entdeckte Dienste hinten angehaengt werden
DEFAULT_SERVICE_RANK=10000
DEFAULT_SERVICE_SORTING=etx
# unbedingt synchron halten mit "_is_persistent_service_attribute" (der Effizienz wegen getrennt)
PERSISTENT_SERVICE_ATTRIBUTES="service scheme host port protocol path uci_dependency file_dependency rank offset disabled"
LOCAL_BIAS_MODULO=10


get_service_name() {
	local service="$1"
	local scheme="$2"
	local host="$3"
	local port="$4"
	local protocol="$5"
	local path="$6"
	local name="${service}_${scheme}_${host}_${port}_${protocol}"
	[ -n "${path#/}" ] && name="${name}_${path#/}"
       	echo "$name" | sed 's/[^A-Za-z0-9_]/_/g'
}


# Aktualisiere den Zeitstempel und die Entfernung (etx) eines Dienstes
notify_service() {
	trap "error_trap notify_service '$*'" $GUARD_TRAPS
	local service="$1"
	local scheme="$2"
	local host="$3"
	local port="$4"
	local protocol="$5"
	local path="$6"
	local details="$7"
	local source="$8"
	local service_name=$(get_service_name "$service" "$scheme" "$host" "$port" "$protocol" "$path")
	local now=$(get_time_minute)
	if ! is_existing_service "$service_name"; then
		# diese Attribute sind Bestandteil des Namens und aendern sich nicht
		set_service_value "$service_name" "service" "$service"
		set_service_value "$service_name" "scheme" "$scheme"
		set_service_value "$service_name" "host" "$host"
		set_service_value "$service_name" "port" "$port"
		set_service_value "$service_name" "protocol" "$protocol"
		set_service_value "$service_name" "path" "$path"
	fi
	set_service_value "$service_name" "details" "$details"
	set_service_value "$service_name" "timestamp" "$now"
	set_service_value "$service_name" "source" "$source"
	update_service_routing_distance "$service_name"
}


## @fn update_service_routing_distance()
## @brief Aktualisiere Routing-Entfernung und Hop-Count eines Dienst-Anbieters
## @param service_name der zu aktualisierende Dienst
## @details Beide Dienst-Werte werden gelöscht, falls der Host nicht route-bar sein sollte.
##   Diese Funktion sollte regelmäßig für alle Hosts ausgeführt werden.
update_service_routing_distance() {
	trap "error_trap update_service_routing_distance '$*'" $GUARD_TRAPS
	local service_name="$1"
	local hop
	local etx
	get_hop_count_and_etx "$(get_service_value "$service_name" "host")" | while read hop etx; do
		set_service_value "$service_name" "distance" "$etx"
		set_service_value "$service_name" "hop_count" "$hop"
	done
}


## @fn is_existing_service()
## @brief Prüfe ob ein Service existiert
## @param service_name der Name des Diensts
## @returns exitcode=0 falls der Dienst existiert
is_existing_service() {
	local service_name="$1"
	[ -n "$service_name" -a -e "$PERSISTENT_SERVICE_STATUS_DIR/$service_name" ] && return 0
	trap "" $GUARD_TRAPS && return 1
}


# Addiere eine Zahl von 0 bis (LOCAL_BIAS_MODULO-1) - abhaengig von der lokalen IP und der IP der Gegenstelle.
# Dadurch koennen wir beim Sortieren strukturelle Ungleichgewichte (z.B. durch alphabetische Sortierung) verhindern.
_add_local_bias_to_host() {
	local ip="$1"
	local host_number=$(echo "$ip$(get_local_bias_number)" | md5sum | sed 's/[^0-9]//g')
	head -1 | awk '{ print $1 + ('$host_number' % '$LOCAL_BIAS_MODULO') }'
}


# Ermittle die Service-Prioritaet eines Dienstes.
# Der Wert ist beliebig und nur im Vergleich mit den Prioritaeten der anderen Dienste verwendbar.
# Als optionaler zweiter Parameter kann die Sortierung uebergeben werden. Falls diese nicht uebergeben wurde,
# wird die aktuell konfigurierte Sortierung benutzt.
# Sollte ein Dienst ein "priority"-Attribut tragen, dann wird die uebliche Dienst-Sortierung aufgehoben
# und lediglich "priority" (und gegebenenfalls separat "offset") beachtet.
get_service_priority() {
	trap "error_trap get_service_priority '$*'" $GUARD_TRAPS
	local service_name="$1"
	local sorting="${2:-}"
	local priority=$(get_service_value "$service_name" "priority")
	local rank
	# priority wird von nicht-olsr-Clients verwendet (z.B. mesh-Gateways mit oeffentlichen IPs)
	if [ -n "$priority" ]; then
		# dieses Ziel traegt anscheinend keine Routing-Metrik
		local offset=$(get_service_value "$service_name" "offset" "0")
		echo "$((priority + offset))"
	else
		# wir benoetigen Informationen fuer Ziele mit Routing-Metriken
		local distance=$(get_service_value "$service_name" "distance")
		# aus Performance-Gruenden kommt die Sortierung manchmal von aussen
		[ -z "$sorting" ] && sorting=$(get_service_sorting)
		if [ "$sorting" = "etx" -o "$sorting" = "hop" ]; then
			# keine Entfernung -> nicht erreichbar -> leeres Ergebnis
			[ -z "$distance" ] && return 0
			get_distance_with_offset "$service_name"
		elif [ "$sorting" = "manual" ]; then
			get_service_value "$service_name" "rank" "$DEFAULT_SERVICE_RANK"
		else
			msg_info "Unknown sorting method for services: $sorting"
			echo 1
		fi
	fi | get_int_multiply 1000 | _add_local_bias_to_host "$(get_service_value "$service_name" "host")"
}


get_distance_with_offset() {
	trap "error_trap get_distance_with_offset '$*'" $GUARD_TRAPS
	local service_name="$1"
	local sorting=$(get_service_sorting)
	local distance=$(get_service_value "$service_name" "distance")
	local base_value=
	[ -z "$distance" ] && return 0
	local offset=$(get_service_value "$service_name" "offset")
	[ -z "$offset" ] && offset=0
	if [ "$sorting" = "etx" ]; then
		base_value="$distance"
	elif [ "$sorting" = "hop" ]; then
		base_value=$(get_service_value "$service_name" "hop_count")
	else
		msg_debug "get_distance_with_offset: sorting '$sorting' not implemented"
	fi
	[ -n "$base_value" ] && echo "$base_value" "$offset" | awk '{ print $1 + $2 }'
	return 0
}


set_service_sorting() {
	trap "error_trap set_service_sorting '$*'" $GUARD_TRAPS
	local new_sorting="$1"
	local old_sorting=$(get_service_sorting)
	[ "$old_sorting" = "$new_sorting" ] && return 0
	[ "$new_sorting" != "manual" -a "$new_sorting" != "hop" -a "$new_sorting" != "etx" ] && \
		msg_info "Warning: Ignoring unknown sorting method: $new_sorting" && \
		trap "" $GUARD_TRAPS && return 1
	uci set "on-core.settings.service_sorting=$new_sorting"
	apply_changes on-core
}


# Liefere die aktuelle Sortier-Methode.
# Falls eine ungueltige Sortier-Methode gesetzt ist, wird diese auf die Standard-Sortierung zurueckgesetzt.
# Die Ausgabe dieser Funktion ist also in jedem Fall eine gueltige Sortier-Methode.
get_service_sorting() {
	trap "error_trap get_service_sorting '$*'" $GUARD_TRAPS
	local sorting=$(uci_get "on-core.settings.service_sorting")
	if [ "$sorting" = "manual" -o "$sorting" = "hop" -o "$sorting" = "etx" ]; then
		# zulaessige Sortierung
		echo -n "$sorting"
	else
		# unbekannte Sortierung: dauerhaft setzen
		# keine Warnung falls die Sortierung nicht gesetzt wurde
		[ -n "$sorting" ] && msg_info "Warning: coercing unknown sorting method: $sorting -> $DEFAULT_SERVICE_SORTING"
		uci set "on-core.settings.service_sorting=$DEFAULT_SERVICE_SORTING"
		echo -n "$DEFAULT_SERVICE_SORTING"
	fi
	return 0
}


sort_services_by_priority() {
	trap "error_trap sort_services_by_priority '$*'" $GUARD_TRAPS
	local service_name
	local priority
	local sorting=$(get_service_sorting)
	while read service_name; do
		priority=$(get_service_priority "$service_name" "$sorting")
		# keine Entfernung (nicht erreichbar) -> ganz nach hinten sortieren (schmutzig, aber wohl ausreichend)
		[ -z "$priority" ] && priority=999999999999999999999999999999999999999
		echo "$priority" "$service_name"
	done | sort -n | awk '{print $2}'
}


## @fn sort_services_by()
## @brief Sortiere den eingegeben Strom von Dienstnamen und gib eine sortierte Liste entsprechende des Arguments aus.
## @param sort_column Die Spalte, anhand deren Inhalt die Auswertung und Sortierung stattfinden soll.
sort_services_by() {
	trap "error_trap sort_services_by '$*'" $GUARD_TRAPS
	local sort_column="$1"
	local service_name
	while read service_name; do
		value=$(get_service_value "$service_name" "$sort_column" "_")
		echo "$value" "$service_name"
	done | sort -n | awk '{print $2}'
}


## @fn filter_reachable_services()
## @brief Filtere aus einer Reihe eingehender Dienste diejenigen heraus, die erreichbar sind.
## @details Die Dienst-Namen werden über die Standardeingabe gelesen und an
##   die Standardausgabe weitergeleitet, falls der Dienst erreichbar sind.
filter_reachable_services() {
	local service_name
	while read service_name; do
		[ -n "$(get_service_value "$service_name" "distance")" ] && echo "$service_name" || true
	done
}


## @fn filter_enabled_services()
## @brief Filtere aus einer Reihe eingehender Dienste diejenigen heraus, die nicht manuell ausgeblendet wurden.
## @details Die Dienst-Namen werden über die Standardeingabe gelesen und an
##   die Standardausgabe weitergeleitet, falls der Dienst nicht abgewählt wurde.
filter_enabled_services() {
	local service_name
	while read service_name; do
		uci_is_false "$(get_service_value "$service_name" "disabled" "false")" && echo "$service_name" || true
	done
}


## @fn pipe_service_attribute()
## @brief Liefere zu einer Reihe von Diensten ein gewähltes Attribut dieser Dienste zurück.
## @param key Der Name eines Dienst-Attributs
## @param default Der Standard-Wert wird anstelle des Attribut-Werts verwendet, falls dieser leer ist.
## @details Die Dienstenamen werden via Standardeingabe erwartet. Auf der Standardausgabe wird für
##   einen Dienst entweder ein Wert oder nichts ausgeliefert. Keine Ausgabe erfolgt, falls der
##   Wert des Dienste-Attributs leer ist. Bei der Eingabe von mehreren Diensten werden also
##   eventuell weniger Zeilen ausgegeben, als eingelesen wurden.
##   Falls der optionale zweite 'default'-Parameter nicht leer ist, dann wird bei einem leeren
##   Ergebnis stattdessen dieser Wert ausgegeben. Der 'default'-Parameter sorgt somit dafür, dass
##   die Anzahl der eingelesenen Zeilen in jedem Fall mit der Anzahl der ausgegebenen Zeilen
##   übereinstimmt.
pipe_service_attribute() {
	local key="$1"
	local default="${2:-}"
	local service_name
	local value
	while read service_name; do
		value=$(get_service_value "$service_name" "$key")
		[ -z "$value" ] && value="$default"
		[ -n "$value" ] && echo "$value" || true
	done
}


## @fn get_services()
## @param service_types ein oder mehrere Service-Typen
## @brief Liefere alle Dienste zurueck, die einem der angegebenen Typen zugeordnet sind.
## Falls keine Parameter übergeben wurden, dann werden alle Dienste ungeachtet ihres Typs ausgegeben.
get_services() {
	trap "error_trap get_services '$*'" $GUARD_TRAPS
	local services
	local service_type
	local fname_persist
	if [ $# -eq 0 ]; then
		# alle Dienste ausgeben
		# kein Dienste-Verzeichnis? Keine Ergebnisse ...
		[ -e "$PERSISTENT_SERVICE_STATUS_DIR" ] || return 0
		find "$PERSISTENT_SERVICE_STATUS_DIR" -type f | while read fname_persist; do
			# leere Dateien ignorieren; die anderen als Dienstnamen ausgeben
			[ -s "$fname_persist" ] && basename "$fname_persist" || true
		done
	else
		# liefere alle Dienste mit dem passenden "service"-Attribut
		services=$(get_services)
		# falls keine Dienste bekannt sind, dann liefere auch keine Leerzeile zurueck
		[ -z "$services" ] && return 0
		for service_type in "$@"; do
			echo "$services" | filter_services_by_value "service=$service_type"
		done
	fi
}


## @fn filter_services_by_value()
## @param key_values beliebige Anzahl von "SCHLUESSEL=WERT"-Kombinationen
## @details Als Parameter koennen beliebig viele "key=value"-Schluesselpaare angegeben werden.
## Nur diejenigen Dienste, auf die alle Bedingungen zutreffen, werden zurueckgeliefert.
## Sind keine Parameter gegeben, dann werden alle eingegebenen Dienste ausgeliefert
filter_services_by_value() {
	local service_name
	local key
	local value
	while read service_name; do
		for condition in "$@"; do
			key=$(echo "$condition" | cut -f 1 -d =)
			value=$(echo "$condition" | cut -f 2- -d =)
			[ "$value" = "$(get_service_value "$service_name" "$key")" ] || continue 2
		done
		# alle Bedingungen trafen zu
		echo "$service_name"
	done
	return 0
}


# Pruefe ob der Schluessel in der persistenten oder der volatilen Datenbank gespeichert werden soll.
# Ziel ist erhoehte Geschwindigkeit und verringerte Schreibzugriffe.
# Diese Liste muss synchron gehalten werden mit PERSISTENT_SERVICE_ATTRIBUTES.
_is_persistent_service_attribute() {
	[ "$1" = "service" \
		-o "$1" = "scheme" \
		-o "$1" = "host" \
		-o "$1" = "port" \
		-o "$1" = "protocol" \
		-o "$1" = "path" \
		-o "$1" = "uci_dependency" \
		-o "$1" = "file_dependency" \
		-o "$1" = "rank" \
		-o "$1" = "offset" \
		-o "$1" = "disabled" \
		] && return 0
	trap "" $GUARD_TRAPS && return 1
}


# Setzen eines Werts fuer einen Dienst.
# Je nach Schluesselname wird der Inhalt in die persistente uci- oder
# die volatile tmpfs-Datenbank geschrieben.
set_service_value() {
	local service_name="$1"
	local attribute="$2"
	local value="$3"
	local dirname
	[ -z "$service_name" ] \
		&& msg_info "Error: no service given for attribute change ($attribute=$value)" \
		&& trap "" $GUARD_TRAPS && return 1
	if _is_persistent_service_attribute "$attribute"; then
		dirname="$PERSISTENT_SERVICE_STATUS_DIR"
	else
		dirname="$VOLATILE_SERVICE_STATUS_DIR"
	fi
	mkdir -p "$dirname"
	_set_file_dict_value "$dirname/$service_name" "$attribute" "$value"
}


## @fn get_service_value()
## @brief Auslesen eines Werts aus der Service-Datenbank.
## @param key Der Name eines Dienst-Attributs
## @param default Der Standard-Wert wird anstelle des Attribut-Werts verwendet, falls dieser leer ist.
## @details Falls das Attribut nicht existiert, wird ein leerer Text zurückgeliefert.
##   Es gibt keinen abschließenden Zeilenumbruch.
get_service_value() {
	local service_name="$1"
	local attribute="$2"
	local default="${3:-}"
	local value
	local dirname
	[ -z "$service_name" ] \
		&& msg_info "Error: no service given for attribute request ('$attribute')" \
		&& trap "" $GUARD_TRAPS && return 1
	if _is_persistent_service_attribute "$attribute"; then
		dirname="$PERSISTENT_SERVICE_STATUS_DIR"
	else
		dirname="$VOLATILE_SERVICE_STATUS_DIR"
	fi
	value=$(_get_file_dict_value "$dirname/$service_name" "$attribute")
	[ -n "$value" ] && echo -n "$value" || echo -n "$default"
	return 0
}


# Liefere die Suffixe aller Schluessel aus der Service-Attribut-Datenbank,
# die mit dem gegebenen Praefix uebereinstimmen.
get_service_attributes() {
	local service_name="$1"
	_get_file_dict_keys "$PERSISTENT_SERVICE_STATUS_DIR/$service_name" ""
	_get_file_dict_keys "$VOLATILE_SERVICE_STATUS_DIR/$service_name" ""
}


# menschenfreundliche Ausgabe der aktuell angemeldeten Dienste
print_services() {
	trap "error_trap print_services '$*'" $GUARD_TRAPS
	local service_name
	local attribute
	local value
	get_services | while read service_name; do
		echo "$service_name"
		get_service_attributes "$service_name" | while read attribute; do
			value=$(get_service_value "$service_name" "$attribute")
			echo -e "\t$attribute=$value"
		done
	done
	return 0
}


# Speichere das angegebene uci-Praefix als eine von einem Service abhaengige Konfiguration.
# Dies ist sinnvoll fuer abgeleitete VPN-Konfigurationen oder Portweiterleitungen.
# Schnittstelle: siehe _add_service_dependency
service_add_uci_dependency() {
	_add_service_dependency "uci_dependency" "$@"
}


# Speichere einen Dateinamen als Abhaengigkeit eines Service.
# Dies ist sinnvoll fuer Dateien, die nicht mehr gebraucht werden, sobald der Service entfernt wird.
# Schnittstelle: siehe _add_service_dependency
service_add_file_dependency() {
	_add_service_dependency "file_dependency" "$@"
}


# Speichere eine Abhaengigkeit fuer einen Dienst.
# Parameter: Service-Name
# Parameter: textuelle Darstellung einer Abhaengigkeit (ohne Leerzeichen)
_add_service_dependency() {
	trap "error_trap _add_service_dependency '$*'" $GUARD_TRAPS
	local dependency="$1"
	local service_name="$2"
	local token="$3"
	local deps=$(get_service_value "$service_name" "$dependency")
	local dep
	for dep in $deps; do
		# schon vorhanden -> fertig
		[ "$dep" = "$token" ] && return 0 || true
	done
	if [ -z "$deps" ]; then
		deps="$token"
	else
		deps="$deps $token"
	fi
	set_service_value "$service_name" "$dependency" "$deps"
}


# Entferne alle mit diesem Service verbundenen Konfigurationen (inkl. Rekonfiguration von firewall, etc.).
cleanup_service_dependencies() {
	trap "error_trap cleanup_service_dependencies '$*'" $GUARD_TRAPS
	local service_name="$1"
	local dep
	local filename
	local branch
	# Dateien loeschen
	for filename in $(get_service_value "$service_name" "file_dependency"); do
		rm -f "$filename"
	done
	# uci-Sektionen loeschen
	for dep in $(get_service_value "$service_name" "uci_dependency"); do
		uci_delete "$dep"
		# gib die oberste config-Ebene aus - fuer spaeteres "apply_changes"
		echo "$dep" | cut -f 1 -d .
	done | sort | uniq | while read branch; do
		apply_changes "$branch"
	done
	set_service_value "$service_name" "uci_dependency" ""
}


get_service_description() {
	trap "error_trap get_service_description '$*'" $GUARD_TRAPS
	local service_name="$1"
	local scheme=$(get_service_value "$service_name" "scheme")
	local host=$(get_service_value "$service_name" "host")
	local port=$(get_service_value "$service_name" "port")
	local proto=$(get_service_value "$service_name" "proto")
	local details=$(get_service_value "$service_name" "details")
	echo "$scheme://$host:$port ($proto) $details"
}


delete_service() {
	trap "error_trap delete_service '$*'" $GUARD_TRAPS
	local service_name="$1"
	[ -z "$service_name" ] && msg_info "Error: no service given for deletion" && trap "" $GUARD_TRAPS && return 1
	cleanup_service_dependencies "$service_name"
	rm -f "$PERSISTENT_SERVICE_STATUS_DIR/$service_name"
	rm -f "$VOLATILE_SERVICE_STATUS_DIR/$service_name"
}


# Durchlaufe alle Dienste und verteile Rangziffern ohne Doppelung an alle Dienste.
# Die Dienst-Arten (z.B. DNS und UGW) werden dabei nicht beachtet.
# Die Rangziffern sind anschliessend streng monoton aufsteigend - beginnend bei 1.
# Falls aktuell die manuelle Sortierung aktiv ist, wird deren Reihenfolge beibehalten.
# Ansonsten basiert die Vergabe der Rangziffern auf der Reihenfolge entsprechend der aktuell aktiven Sortierung.
_distribute_service_ranks() {
	local service_name
	local index=1
	get_services | sort_services_by_priority | while read service_name; do
		set_service_value "$service_name" "rank" "$index"
		: $((index++))
	done
}


## @fn move_service_up()
## @brief Verschiebe einen Dienst in der Dienst-Sortierung um eine Stufe nach oben
## @param service_name der zu verschiebende Dienst
## @details Für verschiedene Sortier-Modi hat dies verschiedene Auswirkungen:
##   * manual: Verschiebung vor den davorplatzierten Dienst desselben Typs
##   * etx/hop: Reduzierung des Offsets um eins
##   Falls keine Dienst-Typen angegeben sind, bewegt der Dienst sich in der globalen Liste nach unten.
move_service_up() {
	trap "error_trap move_service_up '$*'" $GUARD_TRAPS
	local service_name="$1"
	shift
	local sorting=$(get_service_sorting)
	local prev_service=
	local current_service
	local temp
	if [ "$sorting" = "hop" -o "$sorting" = "etx" ]; then
		# reduziere den Offset um eins
		temp=$(get_service_value "$service_name" "offset" 0)
		temp=$(echo "$temp" | awk '{ print $1 - 1 }')
		set_service_value "$service_name" "offset" "$temp"
	elif [ "$sorting" = "manual" ]; then
		get_services "$@" | sort_services_by_priority | while read current_service; do
			if [ "$current_service" = "$service_name" ]; then
				if [ -z "$prev_service" ]; then
					# es gibt keinen Dienst oberhalb des zu verschiebenden
					true
				else
					# wir verschieben den Dienst ueber den davor liegenden
					temp=$(get_service_value "$prev_service" "rank" "$DEFAULT_SERVICE_RANK")
					# ziehe einen halben Rang ab
					temp=$(echo "$temp" | awk '{ print $1 - 0.5 }')
					set_service_value "$service_name" "rank" "$temp"
					# erneuere die Rang-Vergabe
					_distribute_service_ranks
				fi
				# wir sind fertig
				break
			fi
			prev_service="$current_service"
		done
	else
		msg_info "Warning: [move_service_up] sorting method is not implemented: $sorting"
	fi
}


## @fn move_service_down()
## @brief Verschiebe einen Dienst in der Dienst-Sortierung um eine Stufe nach unten
## @param service_name der zu verschiebende Dienst
## @details Für verschiedene Sortier-Modi hat dies verschiedene Auswirkungen:
##   * manual: Verschiebung hinter den dahinterliegenden Dienst desselben Typs
##   * etx/hop: Erhöhung des Offsets um eins
##   Falls keine Dienst-Typen angegeben sind, bewegt der Dienst sich in der globalen Liste nach unten.
move_service_down() {
	trap "error_trap move_service_down '$*'" $GUARD_TRAPS
	local service_name="$1"
	shift
	local sorting=$(get_service_sorting)
	local prev_service=
	local current_service
	local temp
	if [ "$sorting" = "hop" -o "$sorting" = "etx" ]; then
		# reduziere den Offset um eins
		temp=$(get_service_value "$service_name" "offset" 0)
		temp=$(echo "$temp" | awk '{ print $1 + 1 }')
		set_service_value "$service_name" "offset" "$temp"
	elif [ "$sorting" = "manual" ]; then
		get_services "$@" | sort_services_by_priority | while read current_service; do
			if [ "$prev_service" = "$service_name" ]; then
				# wir verschieben den Dienst hinter den danach liegenden
				temp=$(get_service_value "$current_service" "rank" "$DEFAULT_SERVICE_RANK")
				# fuege einen halben Rang hinzu
				temp=$(echo "$temp" | awk '{ print $1 + 0.5 }')
				set_service_value "$service_name" "rank" "$temp"
				# erneuere die Rang-Vergabe
				_distribute_service_ranks
				# wir sind fertig
				break
			fi
			prev_service="$current_service"
		done
	else
		msg_info "Warning: [move_service_down] sorting method is not implemented: $sorting"
	fi
}


## @fn move_service_top()
## @brief Verschiebe einen Dienst an die Spitze der Dienst-Sortierung
## @param service_name der zu verschiebende Dienst
## @param service_types ein oder mehrere Dienst-Typen, auf die die Ermittlung der Dienst-Liste begrenzt werden soll (z.B. "gw" "ugw")
## @details Der Dienst steht anschließend direkt vor dem bisher führenden Dienst der ausgewählten Typen (falls angegeben).
##   Falls keine Dienst-Typen angegeben sind, bewegt der Dienst sich in der globalen Liste an die Spitze.
move_service_top() {
	trap "error_trap move_service_top '$*'" $GUARD_TRAPS
	local service_name="$1"
	shift
	local top_service=$(get_services "$@" | sort_services_by_priority | head -1)
	local sorting=$(get_service_sorting)
	local top_rank
	local new_rank
	local top_distance
	local our_distance
	local current_offset
	local new_offset
	# kein top-Service oder wir sind bereits ganz oben -> Ende
	[ -z "$top_service" -o "$top_service" = "$service_name" ] && return 0
	if [ "$sorting" = "hop" -o "$sorting" = "etx" ]; then
		top_distance=$(get_distance_with_offset "$top_service")
		our_distance=$(get_distance_with_offset "$service_name")
		[ -z "$our_distance" ] && msg_info "Failed to move unreachable service ('$service_name') to top" && return 0
		current_offset=$(get_service_value "$service_name" "offset" 0)
		# wir verschieben unseren Offset, auf dass wir knapp ueber "top" stehen
		new_offset=$(echo | awk "{ print $current_offset + int($top_distance - $our_distance) - 1 }")
		set_service_value "$service_name" "offset" "$new_offset"
	elif [ "$sorting" = "manual" ]; then
		# setze den Rang des Dienstes auf den top-Dienst minus 0.5
		top_rank=$(get_service_value "$top_service" "rank" "$DEFAULT_SERVICE_RANK")
		new_rank=$(echo "$top_rank" | awk '{ print $1 - 0.5 }')
		set_service_value "$service_name" "rank" "$new_rank"
		# erneuere die Rang-Vergabe
		_distribute_service_ranks
	else
		msg_info "Warning: [move_service_top] sorting method is not implemented: $sorting"
	fi
}


## @fn get_service_detail()
## @brief Ermittle den Wert eines Schlüssel-Wert-Paars im "details"-Attribut eines Diensts
## @param service_name Name eines Diensts
## @param key Name des Schlüssels
## @param default dieser Wert wird zurückgeliefert, falls der Schlüssel nicht gefunden wurde
## @returns den ermittelten Wert aus dem Schlüssel-Wert-Paar
get_service_detail() {
	local service_name="$1"
	local key="$2"
	local default="${3:-}"
	local value=$(get_service_value "$service_name" "details" | get_from_key_value_list "$key" ":")
	[ -n "$value" ] && echo -n "$value" || echo -n "$default"
	return 0
}


## @fn set_service_detail()
## @brief Setze den Wert eines Schlüssel-Wert-Paars im "details"-Attribut eines Diensts
## @param service_name Name eines Diensts
## @param key Name des Schlüssels
## @param value der neue Wert
## @details Ein leerer Wert löscht das Schlüssel-Wert-Paar.
set_service_detail() {
	local service_name="$1"
	local key="$2"
	local value="$3"
	local new_details=$(get_service_value "$service_name" "details" | set_in_key_value_list "$key" ":" "$value")
	set_service_value "$service_name" "details" "$new_details"
	return 0
}


get_service_age() {
	local service_name="$1"
	local timestamp=$(get_service_value "$service_name" "timestamp")
	[ -z "$timestamp" ] && return 0
	echo "$(get_time_minute)" "$timestamp" | awk '{ print $1 - $2 }'
}


# Liefere eine Semikolon-separierte Liste von Service-Eigenschaften zurueck.
# Jede Eigenschaft wird folgendermassen ausgedrueckt:
#  type|source|key[|default]
# Dabei sind folgende Inhalte moeglich:
#  type: Rueckgabetyp (string, number, bool)
#  source: Quelle der Informationen (value, detail, function, id)
#  key: Name des Werts, des Details oder der Funktion
#  default: Standardwert, falls das Ergebnis leer sein sollte
# Wahrheitswerte werden als "true" oder "false" zurueckgeliefert. Alle anderen Rueckgabetypen bleiben unveraendert.
# Das Ergebnis sieht folgendermassen aus:
#   SERVICE_NAME;RESULT1;RESULT2;...
get_service_as_csv() {
	local service_name="$1"
	shift
	local separator=";"
	local specification
	local rtype
	local source
	local key
	local default
	local value
	local func_call
	# Abbruch mit Fehler bei unbekanntem Dienst
	is_existing_service "$service_name" || { trap "" $GUARD_TRAPS && return 1; }
	echo -n "$service_name"
	for specification in "$@"; do
		rtype=$(echo "$specification" | cut -f 1 -d "|")
		source=$(echo "$specification" | cut -f 2 -d "|")
		key=$(echo "$specification" | cut -f 3 -d "|")
		default=$(echo "$specification" | cut -f 4- -d "|")
		# Ermittlung des Funktionsaufrufs
		if [ "$source" = "function" ]; then
			if [ "$rtype" = "bool" ]; then
				"$key" "$service_name" && value="true" || value="false"
			else
				value=$("$key" "$service_name")
			fi
		else
			if [ "$source" = "value" ]; then
				value=$(get_service_value "$service_name" "$key")
			elif [ "$source" = "detail" ]; then
				value=$(get_service_detail "$service_name" "$key")
			else
				msg_info "Unknown service attribute requested: $specification"
				echo -n "${separator}"
				continue
			fi
			[ -z "$value" ] && [ -n "$default" ] && value="$default"
			if [ "$rtype" = "bool" ]; then
				# Pruefung auf wahr/falsch
				value=$(uci_is_true "$value" && echo "true" || echo "false")
			fi
		fi
		echo -n "${separator}${value}"
	done
	# mit Zeilenumbruch abschliessen
	echo
}

# Ende der Doku-Gruppe
## @}
