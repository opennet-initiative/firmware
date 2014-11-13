SERVICES_STATUS_FILE=/tmp/on-services.status



_get_service_key() {
	local service="$1"
	local scheme="$2"
	local host="$3"
	local port="$4"
	local protocol="$5"
	local path="$6"
	local key="${service}_${scheme}_${host}_${port}_${protocol}"
	[ -n "${path#/}" ] && key="${key}_${path#/}"
       	echo "$key" | sed 's/[^A-Za-z0-9_]/_/g'
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
	local key=$(_get_service_key "$service" "$scheme" "$host" "$port" "$protocol" "$path")
	local now=$(date +%s)
	set_service_value "$key" "service" "$service"
	set_service_value "$key" "scheme" "$scheme"
	set_service_value "$key" "host" "$host"
	set_service_value "$key" "port" "$port"
	set_service_value "$key" "protocol" "$protocol"
	set_service_value "$key" "path" "$path"
	set_service_value "$key" "details" "$details"
	set_service_value "$key" "timestamp" "$now"
	set_service_value "$key" "distance" "$(_get_service_target_distance "$key")"
}


_get_service_target_distance() {
	local key="$1"
	local distance=$(get_routing_distance "$(get_service_value "$key" "host")")
	# keine Entfernung -> nicht erreichbar -> leeres Ergebnis
	[ -z "$distance" ] && return 0
	local offset=$(get_service_value "$key" "offset")
	[ -z "$offset" ] && offset=0
	echo "$distance" "$offset" | awk '{ print $1+$2 }'
}


get_sorted_services() {
	local service="$1"
	local key
	local uci_prefix
	local distance
	local disabled
	find_all_uci_sections on-core services "service=$service" | while read uci_prefix; do
		disabled=$(uci_get "${uci_prefix}.service")
		key=$(uci_get "${uci_prefix}.name")
		distance=$(get_service_value "$key" "distance")
		# keine Entfernung -> nicht erreichbar -> ignorieren
		[ -z "$distance" ] && continue
		echo "$distance" "$key"
	done | sort -n | awk '{print $2}'
}


# Pruefe ob der Schluessel in der persistenten oder der volatilen Datenbank gespeichert werden soll.
# Ziel ist erhoehte Geschwindigkeit und verringerte Schreibzugriffe.
_is_persistent_service_attribute() {
	echo "$1" | grep -q -E "^(service|scheme|host|port|protocol|path)$" && return 0
	return 1
}


# Setzen eines Werts fuer einen Dienst.
# Je nach Schluesselname wird der Inhalt in die persistente uci- oder
# die volatile tmpfs-Datenbank geschrieben.
set_service_value() {
	local key="$1"
	local attribute="$2"
	local value="$3"
	local uci_prefix
	if _is_persistent_service_attribute "$attribute"; then
		# Speicherung via uci
		uci_prefix=$(find_first_uci_section on-core services "name=$key")
		if [ -z "$uci_prefix" ]; then
			uci_prefix=on-core.$(uci add on-core services)
			uci set "${uci_prefix}.name=$key"
			# alle neuen Eintraege sind automatisch aktiv
			uci set "${uci_prefix}.enabled=1"
		fi
		uci set "${uci_prefix}.$attribute=$value"
	else
		# Speicherung im tmpfs
		_set_file_dict_value "$SERVICES_STATUS_FILE" "${key}-${attribute}" "$value"
	fi
}


# Auslesen eines Werts aus der Service-Datenbank.
get_service_value() {
	local key="$1"
	local attribute="$2"
	local uci_prefix
	if _is_persistent_service_attribute "$attribute"; then
		local uci_prefix=$(find_first_uci_section on-core services "name=$key")
		[ -z "$uci_prefix" ] && return 0
		uci_get "${uci_prefix}.$attribute"
	else
		_get_file_dict_value "$SERVICES_STATUS_FILE" "${key}-${attribute}"
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
	local key
	local value
	find_all_uci_sections on-core services | while read uci_prefix; do
		name=$(uci_get "${uci_prefix}.name")
		echo "Section '$name'"
		get_service_attributes "$name" | while read key; do
			value=$(get_service_value "$name" "$key")
			echo -e "\t$key=$value"
		done
	done
}

