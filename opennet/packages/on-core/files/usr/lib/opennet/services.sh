SERVICES_STATUS_FILE=/tmp/on-services.status



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


# TODO: andere Varianten hinzufuegen: manuell / usw.
_get_service_target_priority() {
	local service_name="$1"
	local distance=$(get_service_value "$service_name" "distance")
	# keine Entfernung -> nicht erreichbar -> leeres Ergebnis
	[ -z "$distance" ] && return 0
	local offset=$(get_service_value "$service_name" "offset")
	[ -z "$offset" ] && offset=0
	echo "$distance" "$offset" | awk '{ print $1+$2 }'
}


# Liefere die Dienst-Namen aller ausgewaehlten Dienste, die erreichbar sind.
# Ein oder mehrere Dienst-Typen koennen angegeben werden.
get_sorted_services() {
	local service
	local service_name
	local uci_prefix
	local priority
	# hole alle Dienste aus den angegebenen Klassen (z.B. "gw ugw")
	for service in "$@"; do
		find_all_uci_sections on-core services "service=$service"
	done | while read uci_prefix; do
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
	local uci_prefix
	if _is_persistent_service_attribute "$attribute"; then
		uci_prefix=$(get_service_uci_prefix "$service_name")
		[ -z "$uci_prefix" ] && return 0
		uci_get "${uci_prefix}.$attribute"
	else
		_get_file_dict_value "$SERVICES_STATUS_FILE" "${service_name}-${attribute}"
	fi
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

