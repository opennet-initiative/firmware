SERVICES_STATUS_FILE=/tmp/on-services.status
# fuer die Sortierung von Gegenstellen benoetigen wir ein lokales Salz, um strukturelle Bevorzugungen (z.B. von UGW-Hosts) zu vermeiden.
LOCAL_BIAS_NUMBER=$(get_main_ip | sed 's/[^0-9]//')
# eine grosse Zahl sorgt dafuer, dass neu entdeckte Dienste hinten angehaengt werden
DEFAULT_RANK=10000
DEFAULT_SERVICE_SORTING=etx



_get_service_name() {
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


# Aktualisiere den Zeitstempel und die Entfernung eines Dienstes
# Es wird _kein_ "uci commit on-core" ausgefuehrt.
notify_service() {
	local service="$1"
	local scheme="$2"
	local host="$3"
	local port="$4"
	local protocol="$5"
	local path="$6"
	local details="$7"
	local service_name=$(_get_service_name "$service" "$scheme" "$host" "$port" "$protocol" "$path")
	local now=$(get_time_minute)
	set_service_value "$service_name" "service" "$service"
	set_service_value "$service_name" "scheme" "$scheme"
	set_service_value "$service_name" "host" "$host"
	set_service_value "$service_name" "port" "$port"
	set_service_value "$service_name" "protocol" "$protocol"
	set_service_value "$service_name" "path" "$path"
	set_service_value "$service_name" "details" "$details"
	set_service_value "$service_name" "timestamp" "$now"
	set_service_value "$service_name" "distance" "$(get_routing_distance "$host")"
	set_service_value "$service_name" "hop_count" "$(get_hop_count "$host")"
	set_service_value "$service_name" "priority" "$(_get_service_target_priority "$service_name")"
}


# Addiere 1 oder 0 - abhaengig von der lokalen IP und der IP der Gegenstelle.
# Dadurch koennen wir beim Sortieren strukturelle Ungleichgewichte (z.B. durch alphabetische Sortierung) verhindern.
_add_local_bias() {
	local ip
        local host_number=$(echo "$ip" | sed 's/[^0-9]//')
	awk '{print ($1+'$LOCAL_BIAS_NUMBER'+'$host_number')%2}')
}


# TODO: andere Varianten hinzufuegen: manuell / usw.
_get_service_target_priority() {
	local service_name="$1"
	local sorting=$(get_service_sorting)
	local distance=$(_get_distance_with_offset "$service_name")
	local rank
	# keine Entfernung -> nicht erreichbar -> leeres Ergebnis
	[ -z "$distance" ] && return 0
	if [ "$sorting" = "etx" -o "$sorting" = "hop" ]; then
		_get_distance_with_offset "$service_name"
	elif [ "$sorting" = "manual" ]; then
		get_service_value "$service_name" "rank" "$DEFAULT_SERVICE_RANK"
	else
		msg_info "Unknown sorting method for services: $sorting"
		echo 1
	fi | get_int_multiply 1000 | _add_local_bias "$(get_service_value "$service_name" "host")"
}


_get_distance_with_offset() {
	local service_name="$1"
	local sorting=$(get_service_sorting)
	local distance=$(get_service_value "$service_name" "distance")
	local base_value
	[ -z "$distance" ] && return 0
	local offset=$(get_service_value "$service_name" "offset")
	[ -z "$offset" ] && offset=0
	if [ "$sorting" = "etx" ]; then
		base_value="$distance"
	elif [ "$sorting" = "hop" ]; then
		base_value=$(get_service_value "$service_name" "hop_count")
	fi
	echo "$base_value" "$offset" | awk '{ print $1 + $2 }'
}


set_service_sorting() {
	local service_name="$1"
	local new_sorting="$2"
	local old_sorting=$(get_service_sorting)
	[ "$old_sorting" = "$new_sorting" ] && return 0
	[ "$new_sorting" != "manual" -a "$new_sorting" != "hop" -a "$new_sorting" != "etx" ] && \
		msg_info "Warning: Ignoring unknown sorting method: $new_sorting" && \
		return 1
	uci set "on-core.settings.service_sorting=$new_sorting"
	update_service_priorities
	uci commit on-core
}


# Liefere die aktuelle Sortier-Methode.
# Falls eine ungueltige Sortier-Methode gesetzt ist, wird diese auf die Standard-Sortierung zurueckgesetzt.
# Die Ausgabe dieser Funktion ist also in jedem Fall eine gueltige Sortier-Methode.
get_service_sorting() {
	local sorting=$(uci_get "on-core.settings.service_sorting")
	if [ "$new_sorting" = "manual" -o "$new_sorting" = "hop" -o "$new_sorting" = "etx" ]; then
		# zulaessige Sortierung
		echo "$sorting"
	else
		# unbekannte Sortierung: dauerhaft setzen
		# keine Warnung falls die Sortierung nicht gesetzt wurde
		[ -n "$sorting" ] && msg_info "Warning: coercing unknown sorting method: $sorting -> $DEFAULT_SERVICE_SORTING"
		uci set "on-core.settings.service_sorting=$DEFAULT_SERVICE_SORTING"
		echo "$DEFAULT_SERVICE_SORTING"
	fi
	return 0
}


# Liefere die Dienst-Namen aller ausgewaehlten Dienste, die erreichbar sind.
# Ein oder mehrere Dienst-Typen koennen angegeben werden.
get_sorted_services() {
	local service
	local service_name
	local uci_prefix
	local priority
	if [ "$#" -gt 0 ]; then
		# hole alle Dienste aus den angegebenen Klassen (z.B. "gw ugw")
		for service in "$@"; do
			find_all_uci_sections on-core services "service=$service"
		done
	else
		# alle Dienste ohne Typen-Sortierung
		find_all_uci_sections on-core services
	fi ) | while read uci_prefix; do
		service_name=$(uci_get "${uci_prefix}.name")
		# keine Entfernung -> nicht erreichbar -> ignorieren
		[ -z "$(get_service_value "$service_name" "distance")" ] && continue
		priority=$(get_service_value "$service_name" "priority" | get_int_multiply 10000)
		echo "$priority" "$service_name"
	done | sort -n | awk '{print $2}'
}


# Lese Service-Namen via stdin und gib alle angeschalteten ("disabled=0" oder leer) Dienste auf stdout aus.
filter_enabled_services() {
	local service_name
	local disabled
	while read service_name; do
		disabled=$(get_service_value "$service_name" "disabled")
		# abgeschaltet?
		[ -n "$disabled" ] && is_uci_true "$disabled" && continue
		# aktiv!
		echo "$service_name"
	done
}


# Pruefe ob der Schluessel in der persistenten oder der volatilen Datenbank gespeichert werden soll.
# Ziel ist erhoehte Geschwindigkeit und verringerte Schreibzugriffe.
_is_persistent_service_attribute() {
	echo "$1" | grep -q -E "^(service|scheme|host|port|protocol|path|uci_dependency)$" && return 0
	return 1
}


# Setzen eines Werts fuer einen Dienst.
# Je nach Schluesselname wird der Inhalt in die persistente uci- oder
# die volatile tmpfs-Datenbank geschrieben.
set_service_value() {
	local service_name="$1"
	local attribute="$2"
	local value="$3"
	local uci_prefix
	if _is_persistent_service_attribute "$attribute"; then
		# Speicherung via uci
		uci_prefix=$(get_service_uci_prefix "$service_name")
		if [ -z "$uci_prefix" ]; then
			uci_prefix=on-core.$(uci add on-core services)
			uci set "${uci_prefix}.name=$service_name"
		fi
		uci set "${uci_prefix}.$attribute=$value"
	else
		# Speicherung im tmpfs
		_set_file_dict_value "$SERVICES_STATUS_FILE" "${service_name}-${attribute}" "$value"
	fi
}


# Auslesen eines Werts aus der Service-Datenbank.
get_service_value() {
	local service_name="$1"
	local attribute="$2"
	local default="${3:-}"
	local value=
	local uci_prefix
	if _is_persistent_service_attribute "$attribute"; then
		uci_prefix=$(get_service_uci_prefix "$service_name")
		[ -n "$uci_prefix" ] && value=$(uci_get "${uci_prefix}.$attribute")
	else
		value=$(_get_file_dict_value "$SERVICES_STATUS_FILE" "${service_name}-${attribute}")
	fi
	[ -n "$value" ] && echo "$value" || echo "$default"
	return 0
}


# Liefere die Suffixe aller Schluessel aus der Service-Attribut-Datenbank,
# die mit dem gegebenen Praefix uebereinstimmen.
get_service_attributes() {
	local name="$1"
	_get_file_dict_keys "$SERVICES_STATUS_FILE" "${name}-"
}


# menschenfreundliche Ausgabe der aktuell angemeldeten Dienste
print_services() {
	local uci_prefix
	local name
	local attribute
	local value
	find_all_uci_sections on-core services | while read uci_prefix; do
		name=$(uci_get "${uci_prefix}.name")
		echo "Section '$name'"
		get_service_attributes "$name" | while read attribute; do
			value=$(get_service_value "$name" "$attribute")
			echo -e "\t$attribute=$value"
		done
	done
}


get_service_uci_prefix() {
	local service_name="$1"
	shift
	find_first_uci_section on-core services "name=$service_name" "$@"
}



# Speichere das angegebene uci-Praefix als eine von einem Service abhaengige Konfiguration.
# Dies ist sinnvoll fuer abgeleitete VPN-Konfigurationen oder Portweiterleitungen.
# Anschliessend muss "uci commit on-core" aufgerufen werden.
# Schnittstelle: siehe _add_service_dependency
add_service_uci_dependency() {
	_add_service_dependency "uci_dependency" "$@"
}


# Speichere einen Dateinamen als Abhaengigkeit eines Service.
# Dies ist sinnvoll fuer Dateien, die nicht mehr gebraucht werden, sobald der Service entfernt wird.
# Anschliessend muss "uci commit on-core" aufgerufen werden.
# Schnittstelle: siehe _add_service_dependency
add_service_file_dependency() {
	_add_service_dependency "file_dependency" "$@"
}


# Speichere eine Abhaengigkeit fuer einen Dienst.
# Parameter: Service-Name
# Parameter: textuelle Darstellung einer Abhaengigkeit (ohne Leerzeichen)
_add_service_dependency() {
	local dependency="$1"
	local service_name="$2"
	local token="$3"
	local deps=$(get_service_value "$service_name" "$dependency")
	local dep
	for dep in $deps; do
		# schon vorhanden -> fertig
		[ "$dep" = "$token" ] && return 0
	done
	if [ -z "$deps" ]; then
		deps="$token"
	else
		deps="$deps $token"
	fi
	set_service_value "$service_name" "$deps"
}


# Entferne alle mit diesem Service verbundenen Konfigurationen (inkl. Rekonfiguration von firewall, etc.).
# Anschliessend muss "uci commit on-core" aufgerufen werden.
cleanup_service_dependencies() {
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
	set_service_value "$service_name" "uci_dependency"
}


get_service_description() {
	local service_name="$1"
	local scheme=$(get_service_value "$service_name" "scheme")
	local host=$(get_service_value "$service_name" "host")
	local port=$(get_service_value "$service_name" "port")
	local proto=$(get_service_value "$service_name" "proto")
	local details=$(get_service_value "$service_name" "details")
	echo "$scheme://$host:$port ($proto) $details"
}


update_service_priorities() {
	local uci_prefix
	local service_name
	local priority
	find_all_uci_sections on-core services | while read uci_prefix; do
		service_name=$(uci_get "${uci_prefix}.name")
		priority=$(_get_service_target_priority "$service_name")
		set_service_value "$service_name" "priority" "$priority"
	done
}


delete_service() {
	trap "error_trap delete_service $*" $GUARD_TRAPS
	local service_name="$1"
	[ -z "$service_name" ] && msg_info "Error: no service given for deletion" && return 1
	local uci_prefix=$(get_service_uci_prefix "$service_name")
}


# Durchlaufe alle Dienste und verteile Rangziffern ohne Doppelung an alle Dienste.
# Die Dienst-Arten (z.B. DNS und UGW) werden dabei nicht beachtet.
# Die Rangziffern sind anschliessend streng monoton aufsteigend - beginnend bei 1.
# Falls aktuell die manuelle Sortierung aktiv ist, wird deren Reihenfolge beibehalten.
# Ansonsten basiert die Vergabe der Rangziffern auf der Reihenfolge entsprechend der aktuell aktiven Sortierung.
_distribute_service_ranks() {
	local service_name
	local index=1
	get_sorted_services | while read service_name; do
		set_service_value "$service_name" "rank" "$index"
		: $((index++))
	done
}


# Einen Dienst um eine Stufe nach oben bewegen.
# Für verschiedene Sortier-Modi hat dies verschiedene Auswirkungen:
#   manual: Verschiebung vor den davorliegenden Dienst desselben Typs
#   etx/hop: Reduzierung des Offsets um eins
# Parameter: zu verschiebender Service
# Parameter: eine Liste von Dienst-Typen (z.B. "ugw" "gw")
# Falls keine Dienst-Typen angegeben sind, bewegt der Dienst sich in der globalen Liste nach oben.
move_service_up() {
	trap "error_trap move_service_up $*" $GUARD_TRAPS
	local service_name="$1"
	shift
	local sorting=$(get_service_sorting)
	local prev_service=
	local current_service
	local temp
	if [ "$sorting" = "hop" -o "$sorting" = "etx" ]; then
		# reduziere den Offset um eins
		temp=$(get_service_value "$service_name" 0)
		temp=$(echo "$temp" | awk '{ print $1 - 1 }')
		set_service_value "$service_name" "offset" "$temp"
	elif [ "$sorting" = "manual" ]; then
		get_sorted_services "$@" | while read current_service; do
			if [ "$current_service" = "$service_name" ]; then
				if [ -z "$prev_service" ]; then
					# es gibt keinen Dienst oberhalb des zu verschiebenden
					true
				else
					# wir verschieben den Dienst ueber den davor liegenden
					temp=$(get_service_value "$current_server" "rank" "$DEFAULT_SERVICE_RANK")
					# ziehe einen halben Rang ab
					temp=$(echo "$temp" | awk '{ print $1 - 0.5 }')
					set_service_value "$service_name" "rank" "$temp"
					# erneuere die Rang-Vergabe
					_distribute_service_ranks
				fi
			fi
			prev_service="$current_service"
		done
	else
		log_info "Warning: [move_service_up] sorting method is not implemented: $sorting"
	fi
	return 0
	apply_changes on-core
}


# Einen Dienst um eine Stufe nach unten bewegen.
# Für verschiedene Sortier-Modi hat dies verschiedene Auswirkungen:
#   manual: Verschiebung hinter den dahinterliegenden Dienst desselben Typs
#   etx/hop: Erhoehung des Offsets um eins
# Parameter: zu verschiebender Service
# Parameter: eine Liste von Dienst-Typen (z.B. "ugw" "gw")
# Falls keine Dienst-Typen angegeben sind, bewegt der Dienst sich in der globalen Liste nach unten.
move_service_down() {
	trap "error_trap move_service_down $*" $GUARD_TRAPS
	local service_name="$1"
	shift
	local sorting=$(get_service_sorting)
	local prev_service=
	local current_service
	local temp
	if [ "$sorting" = "hop" -o "$sorting" = "etx" ]; then
		# reduziere den Offset um eins
		temp=$(get_service_value "$service_name" 0)
		temp=$(echo "$temp" | awk '{ print $1 + 1 }')
		set_service_value "$service_name" "offset" "$temp"
	elif [ "$sorting" = "manual" ]; then
		get_sorted_services "$@" | while read current_service; do
			if [ "$prev_service" = "$service_name" ]; then
				# wir verschieben den Dienst hinter den danach liegenden
				temp=$(get_service_value "$current_server" "rank" "$DEFAULT_SERVICE_RANK")
				# fuege einen halben Rang hinzu
				temp=$(echo "$temp" | awk '{ print $1 + 0.5 }')
				set_service_value "$service_name" "rank" "$temp"
				# erneuere die Rang-Vergabe
				_distribute_service_ranks
			fi
			prev_service="$current_service"
		done
	else
		log_info "Warning: [move_service_down] sorting method is not implemented: $sorting"
	fi
	apply_changes on-core
}


# Einen Dienst an die Spitze der Dienst-Sortierung verschieben.
# Der Dienst steht anschliessend direkt vor den fuehrenden Dienst der ausgewaehlten Typen (falls angegeben).
# Parameter: zu verschiebender Service
# Parameter: eine Liste von Dienst-Typen (z.B. "ugw" "gw")
# Falls keine Dienst-Typen angegeben sind, bewegt der Dienst sich in der globalen Liste an die Spitze.
move_service_top() {
	trap "error_trap move_service_top $*" $GUARD_TRAPS
	local service_name="$1"
	shift
	local top_service=$(get_sorted_services "$@" | head -1)
	local sorting=$(get_service_sorting)
	local top_rank
	local new_rank
	local top_distance
	local our_distance
	local current_offset
	local new_offset
	# kein top-Service oder wir bereits ganz oben -> Ende
	[ -z "$top_service" -o "$top_service" = "$service_name" ] && return 0
	if [ "$sorting" = "hop" -o "$sorting" = "etx" ]; then
		top_distance=$(_get_distance_with_offset "$top_service")
		our_distance=$(_get_distance_with_offset "$service_distance")
		current_offset=$(get_service_value "$service_name" "offset" 0)
		# wir verschieben unseren Offset, auf dass wir knapp ueber "top" stehen
		new_offset=$(awk "{ $current_offset - int($top_distance - $our_distance) - 1 }")
		set_service_value "$service_name" "offset" "$new_offset"
	elif [ "$sorting" = "manual" ]; then
		# setze den Rang des Dienstes auf den top-Dienst minus 0.5
		top_rank=$(get_service_value "$top_service" "rank" "$DEFAULT_SERVICE_RANK")
		new_rank=$(echo "$top_rank" | awk '{ print $1 - 0.5 }')
		set_service_value "$service_name" "rank" "$new_rank"
		# erneuere die Rang-Vergabe
		_distribute_service_ranks
	else
		log_info "Warning: [move_service_top] sorting method is not implemented: $sorting"
	fi
	apply_changes on-core
}

