## @defgroup services Dienste
## @brief Verwaltung von Diensten (z.B. via olsrd-nameservice announciert)
# Beginn der Doku-Gruppe
## @{

VOLATILE_SERVICE_STATUS_DIR=/tmp/on-services-volatile.d
PERSISTENT_SERVICE_STATUS_DIR=/etc/on-services.d
# eine grosse Zahl sorgt dafuer, dass neu entdeckte Dienste hinten angehaengt werden
DEFAULT_SERVICE_RANK=10000
DEFAULT_SERVICE_SORTING=etx
# Die folgenden Attribute werden dauerhaft (im Flash) gespeichert. Häufige Änderungen sind also eher unerwünscht.
# Gruende fuer ausgefallene/unintuitive Attribute:
#   uci_dependency: später zu beräumende uci-Einträge wollen wir uns merken
#   file_dependency: siehe uci_dependency
#   priority: DNS-entdeckte Dienste enthalten ein "priority"-Attribut, nach einem reboot wieder verfügbar sein sollte
#   rank/offset: Attribute zur Ermittlung der Dienstreihenfolge
#   disabled: der Dienst wurde vom Nutzenden an- oder abgewählt
#   source: die Quelle des Diensts (olsrd/dns/manual) muss erhalten bleiben, um ihn später löschen zu können
# Wir beachten den vorherigen Zustand der Variable, damit andere Module (z.B. on-usergw) diese
# ebenfalls beeinflussen können.
PERSISTENT_SERVICE_ATTRIBUTES="${PERSISTENT_SERVICE_ATTRIBUTES:-} service scheme host port protocol path uci_dependency file_dependency priority rank offset disabled source"
LOCAL_BIAS_MODULO=10
SERVICES_LOG_BASE=/var/log/on-services
# Namenspräfix für weiterzuleitende Dienste
RELAYABLE_SERVICE_PREFIX="proxy-"
UPDATE_TRUSTED_SERVICES_PERIOD_MINUTES=360
USER_SERVICES_URL=https://services.opennet-initiative.de/user-services.csv

# andere Module fügen eventuell weitere URLs hinzu
SERVICES_LIST_URLS="${SERVICES_LIST_URLS:-} $USER_SERVICES_URL"


## @fn get_service_name()
## @brief Ermittle en Namen eines Diensts basierend auf den Dienst-Attributen.
## @details Reihenfolge der Eingabeparameter: SERVICE_TYPE SCHEMA HOST PORT PROTOCOL PATH
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


## @fn notify_service()
## @brief Aktualisiere den Zeitstempel und die Entfernung (etx) eines Dienstes
## @param service z.B. "gw"
## @param scheme z.B. "openvpn"
## @param host z.B. "192.168.2.254"
## @param port z.B. "1600"
## @param path z.B. "/"
## @param protocol z.B. "udp"
## @param details z.B. "via:megumi"
## @returns Der Dienstname wird ausgegeben.
notify_service() {
	trap 'error_trap notify_service "$*"' EXIT
	# wir erwarten sieben Parameter
	[ "$#" -eq 7 ] || [ "$#" -eq 8 ]
	local source="$1"
	shift
	echo "$@" | notify_services "$source"
}


## @fn notify_services()
## @brief Siehe "notify_service" - jedoch effizienter im Umgang mit einer großen Anzahl von Diensten
## @param source Quelle (z.B. "olsr")
## @returns Alle Dienstnamen werden ausgegeben.
notify_services() {
	trap 'error_trap notify_services "$*"' EXIT
	local source="$1"
	local service
	local scheme
	local host
	local port
	local protocol
	local path
	local source
	local details
	local service_name
	local etx
	local hop
	while read -r service scheme host port protocol path details; do
		service_name=$(get_service_name "$service" "$scheme" "$host" "$port" "$protocol" "$path")
		# Diese Attribute duerften sich nicht aendern, aber wir wollen sicherheitshalber lieber kaputten
		# Werten vorbeugen.
		# "details", "timestamp" und "source" sind die flexiblen Werte.
		set_service_value "$service_name" \
			"service" "$service" \
			"scheme" "$scheme" \
			"host" "$host" \
			"port" "$port" \
			"protocol" "$protocol" \
			"path" "$path" \
			"details" "$details" \
			"timestamp" "$(get_uptime_minutes)" \
			"source" "$source"
		get_hop_count_and_etx "$host" | while read -r hop etx; do
			set_service_value "$service_name" \
				"distance" "$etx" \
				"hop_count" "$hop"
		done
		echo "$service_name"
	done
}


## @fn is_existing_service()
## @brief Prüfe ob ein Service existiert
## @param service_name der Name des Diensts
## @returns exitcode=0 falls der Dienst existiert
is_existing_service() {
	local service_name="$1"
	if [ -n "$service_name" ] && [ -e "$PERSISTENT_SERVICE_STATUS_DIR/$service_name" ]; then
		return 0
	else
		trap "" EXIT && return 1
	fi
}


## @fn _get_local_bias_for_service()
## @brief Ermittle eine reproduzierbare Zahl von 0 bis (LOCAL_BIAS_MODULO-1) - abhängig von der lokalen IP und dem Dienstnamen.
## @param service_name der Name des Diensts für den ein Bias-Wert zu ermitteln ist.
## @details Dadurch können wir beim Sortieren strukturelle Bevorzugungen (z.B. durch alphabetische Sortierung) verhindern.
_get_local_bias_for_service() {
	local service_name="$1"
	# lade den Wert aus dem Cache, falls moeglich
	local bias_cache
	bias_cache=$(get_service_value "$service_name" "local_bias")
	if [ -z "$bias_cache" ]; then
		# Die resultierende host_number darf nicht zu gross sein (z.B. mit Exponentendarstellung),
		# da andernfalls awk die Berechnung fehlerhaft durchführt.
		local host_number
		host_number=$(echo "$service_name$(get_local_bias_number)" | md5sum | sed 's/[^0-9]//g')
		# Laenge von 'host_number' reduzieren (die Berechnung schlaegt sonst fehl)
		# Wir fuegen die 1 an den Beginn, um die Interpretation als octal-Zahl zu verhindern (fuehrende Null).
		bias_cache=$(( 1${host_number:0:6} % LOCAL_BIAS_MODULO))
		set_service_value "$service_name" "local_bias" "$bias_cache"
	fi
	echo -n "$bias_cache"
}


# Ermittle die Service-Prioritaet eines Dienstes.
# Der Wert ist beliebig und nur im Vergleich mit den Prioritaeten der anderen Dienste verwendbar.
# Als optionaler zweiter Parameter kann die Sortierung uebergeben werden. Falls diese nicht uebergeben wurde,
# wird die aktuell konfigurierte Sortierung benutzt.
# Sollte ein Dienst ein "priority"-Attribut tragen, dann wird die uebliche Dienst-Sortierung aufgehoben
# und lediglich "priority" (und gegebenenfalls separat "offset") beachtet.
get_service_priority() {
	trap 'error_trap get_service_priority "$*"' EXIT
	local service_name="$1"
	local sorting="${2:-}"
	local priority
	priority=$(get_service_value "$service_name" "priority")
	# priority wird von nicht-olsr-Clients verwendet (z.B. mesh-Gateways mit oeffentlichen IPs)
	local base_priority
	base_priority=$(
		if [ -n "$priority" ]; then
			# dieses Ziel traegt anscheinend keine Routing-Metrik
			local offset
			offset=$(get_service_value "$service_name" "offset" "0")
			echo "$((priority + offset))"
		else
			# wir benoetigen Informationen fuer Ziele mit Routing-Metriken
			# aus Performance-Gruenden kommt die Sortierung manchmal von aussen
			[ -z "$sorting" ] && sorting=$(get_service_sorting)
			if [ "$sorting" = "etx" ] || [ "$sorting" = "hop" ]; then
				get_distance_with_offset "$service_name" "$sorting"
			elif [ "$sorting" = "manual" ]; then
				get_service_value "$service_name" "rank" "$DEFAULT_SERVICE_RANK"
			else
				msg_error "Unknown sorting method for services: $sorting"
				echo 1
			fi
		fi)
	local service_bias
	service_bias=$(_get_local_bias_for_service "$service_name")
	echo "${base_priority:-$DEFAULT_SERVICE_RANK}" | awk '{ print $1 * 1000 + '"$service_bias"'; }'
}


get_distance_with_offset() {
	trap 'error_trap get_distance_with_offset "$*"' EXIT
	local service_name="$1"
	local sorting="${2:-}"
	local distance
	local base_value=
	local offset
	# aus Performance-Gruenden wird manchmal das sorting von aussen vorgegeben
	[ -z "$sorting" ] && sorting=$(get_service_sorting)
	distance=$(get_service_value "$service_name" "distance")
	[ -z "$distance" ] && return 0
	offset=$(get_service_value "$service_name" "offset")
	[ -z "$offset" ] && offset=0
	if [ "$sorting" = "etx" ]; then
		base_value="$distance"
	elif [ "$sorting" = "hop" ]; then
		base_value=$(get_service_value "$service_name" "hop_count")
	else
		msg_debug "get_distance_with_offset: sorting '$sorting' not implemented"
	fi
	[ -n "$base_value" ] && echo "$base_value" "$offset" | awk '{ print $1 + $2 }'
}


set_service_sorting() {
	trap 'error_trap set_service_sorting "$*"' EXIT
	local new_sorting="$1"
	local old_sorting
	old_sorting=$(get_service_sorting)
	[ "$old_sorting" = "$new_sorting" ] && return 0
	if [ "$new_sorting" != "manual" ] && [ "$new_sorting" != "hop" ] && [ "$new_sorting" != "etx" ]; then
		msg_error "Ignoring unknown sorting method: $new_sorting"
		trap "" EXIT && return 1
	else
		uci set "on-core.settings.service_sorting=$new_sorting"
		apply_changes "on-core"
	fi
}


# Liefere die aktuelle Sortier-Methode.
# Falls eine ungueltige Sortier-Methode gesetzt ist, wird diese auf die Standard-Sortierung zurueckgesetzt.
# Die Ausgabe dieser Funktion ist also in jedem Fall eine gueltige Sortier-Methode.
get_service_sorting() {
	trap 'error_trap get_service_sorting "$*"' EXIT
	local sorting
	sorting=$(uci_get "on-core.settings.service_sorting")
	if [ "$sorting" = "manual" ] || [ "$sorting" = "hop" ] || [ "$sorting" = "etx" ]; then
		# zulaessige Sortierung
		echo -n "$sorting"
	else
		# unbekannte Sortierung: dauerhaft setzen
		# keine Warnung falls die Sortierung nicht gesetzt wurde
		[ -n "$sorting" ] && msg_error "coercing unknown sorting method: $sorting -> $DEFAULT_SERVICE_SORTING"
		uci set "on-core.settings.service_sorting=$DEFAULT_SERVICE_SORTING"
		echo -n "$DEFAULT_SERVICE_SORTING"
	fi
	return 0
}


## @fn sort_services_by_priority()
## @brief Sortiere den eingegebenen Strom von Dienstnamen und gib eine nach der Priorität sortierte Liste.
## @details Die Prioritätsinformation wird typischerweise für nicht-mesh-verteilte Dienste verwendet (z.B. den mesh-Tunnel).
sort_services_by_priority() {
	trap 'error_trap sort_services_by_priority "$*"' EXIT
	local service_name
	local priority
	local sorting
	sorting=$(get_service_sorting)
	while read -r service_name; do
		priority=$(get_service_priority "$service_name" "$sorting")
		# keine Entfernung (nicht erreichbar) -> ganz nach hinten sortieren (schmutzig, aber wohl ausreichend)
		[ -z "$priority" ] && priority=999999999999999
		echo "$priority" "$service_name"
	done | sort -n | awk '{print $2}'
}


## @fn filter_reachable_services()
## @brief Filtere aus einer Reihe eingehender Dienste diejenigen heraus, die erreichbar sind.
## @details Die Dienst-Namen werden über die Standardeingabe gelesen und an die Standardausgabe
##   weitergeleitet, falls der Dienst erreichbar sind. "Erreichbarkeit" gilt als erreicht, wenn
##   der Host via olsr route-bar ist oder wenn er als DNS-entdeckter Dienst eine Priorität hat
##   oder wenn er manuell hinzugefügt wurde.
filter_reachable_services() {
	local service_name
	while read -r service_name; do
		{ [ -n "$(get_service_value "$service_name" "distance")" ] \
			|| [ -n "$(get_service_value "$service_name" "priority")" ] \
			|| [ "$(get_service_value "$service_name" "source")" = "manual" ]
		} && echo "$service_name"
		true
	done
}


## @fn filter_enabled_services()
## @brief Filtere aus einer Reihe eingehender Dienste diejenigen heraus, die nicht manuell ausgeblendet wurden.
## @details Die Dienst-Namen werden über die Standardeingabe gelesen und an
##   die Standardausgabe weitergeleitet, falls der Dienst nicht abgewählt wurde.
filter_enabled_services() {
	local service_name
	local disabled
	while read -r service_name; do
		disabled=$(get_service_value "$service_name" "disabled")
		[ -n "$disabled" ] && uci_is_true "$disabled" && continue
		echo "$service_name"
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
##   Die Ausgabe besteht aus dem Service-Namen und dem Attributinhalt (getrennt durch einen Tabulator).
pipe_service_attribute() {
	local key="$1"
	local default="${2:-}"
	local service_name
	local value
	while read -r service_name; do
		[ -z "$service_name" ] && continue
		value=$(get_service_value "$service_name" "$key")
		[ -z "$value" ] && value="$default"
		[ -n "$value" ] && printf '%s\t%s\n' "$service_name" "$value"
		true
	done
}


## @fn get_services()
## @param service_type (optional) ein Service-Typ
## @brief Liefere alle Dienste zurueck, die dem angegebenen Typ zugeordnet sind.
##    Falls kein Typ angegben wird, dann werden alle Dienste ungeachtet ihres Typs ausgegeben.
get_services() {
	trap 'error_trap get_services "$*"' EXIT
	local service_type="${1:-}"
	# alle Dienste ausgeben
	# kein Dienste-Verzeichnis? Keine Ergebnisse ...
	[ -e "$PERSISTENT_SERVICE_STATUS_DIR" ] || return 0
	find "$PERSISTENT_SERVICE_STATUS_DIR" -type f -size +1c -print0 \
		| xargs -0 -r -n 1 basename \
		| if [ -n "$service_type" ]; then
			filter_services_by_value "service" "$service_type"
		else
			cat -
		fi
}


## @fn filter_services_by_value()
## @param key ein Schlüssel
## @param value ein Wert
## @details Als Parameter kann ein "key/value"-Schluesselpaar angegeben werden.
##   Nur diejenigen Dienste, auf die diese Bedingung zutrifft, werden zurueckgeliefert.
filter_services_by_value() {
	local key="$1"
	local value="$2"
	local service_name
	while read -r service_name; do
		[ "$value" != "$(get_service_value "$service_name" "$key")" ] || echo "$service_name"
	done
}


## @fn set_service_value()
## @brief Setzen eines oder mehrerer Werte fuer einen Dienst.
## Je nach Schluesselname wird der Inhalt in die persistente uci- oder
# die volatile tmpfs-Datenbank geschrieben.
set_service_value() {
	local service_name="$1"
	shift
	local attribute
	local value
	local dirname
	[ -z "$service_name" ] \
		&& msg_error "No service given for attribute change ($attribute=$value)" \
		&& trap "" EXIT && return 1
	while [ "$#" -gt 0 ]; do
		attribute="$1"
		value="$2"
		shift 2
		# unverändert? ueberspringen ...
		[ "$value" = "$(get_service_value "$service_name" "$attribute")" ] && continue
		if echo "$PERSISTENT_SERVICE_ATTRIBUTES" | grep -q -w "$attribute"; then
			dirname="$PERSISTENT_SERVICE_STATUS_DIR"
		else
			dirname="$VOLATILE_SERVICE_STATUS_DIR"
		fi
		_set_file_dict_value "$dirname/$service_name" "$attribute" "$value"
	done
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
		&& msg_error "No service given for attribute request ('$attribute')" \
		&& trap "" EXIT && return 1
	value=$(_get_file_dict_value "$attribute" "$PERSISTENT_SERVICE_STATUS_DIR/$service_name" "$VOLATILE_SERVICE_STATUS_DIR/$service_name")
	[ -n "$value" ] && echo -n "$value" || echo -n "$default"
	return 0
}


# Liefere die Suffixe aller Schluessel aus der Service-Attribut-Datenbank,
# die mit dem gegebenen Praefix uebereinstimmen.
get_service_attributes() {
	_get_file_dict_keys "$PERSISTENT_SERVICE_STATUS_DIR/$1" "$VOLATILE_SERVICE_STATUS_DIR/$1"
}


## @fn print_services()
## @brief menschenfreundliche Ausgabe der aktuell angemeldeten Dienste
## @param service_type (optional) ein Service-Type
## @returns Ausgabe der bekannten Dienste (für Menschen - nicht parsebar)
print_services() {
	trap 'error_trap print_services "$*"' EXIT
	local service_name
	local attribute
	local value
	for service_name in $(get_services "$@"); do
		echo "$service_name"
		for attribute in $(get_service_attributes "$service_name"); do
			printf '\t%s=%s\n' "$attribute" "$(get_service_value "$service_name" "$attribute")"
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
	trap 'error_trap _add_service_dependency "$*"' EXIT
	local dependency="$1"
	local service_name="$2"
	local token="$3"
	local deps
	local dep
	deps=$(get_service_value "$service_name" "$dependency")
	for dep in $deps; do
		# schon vorhanden -> fertig
		[ "$dep" = "$token" ] && return 0
		true
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
	trap 'error_trap cleanup_service_dependencies "$*"' EXIT
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
	done | sort | uniq | while read -r branch; do
		apply_changes "$branch"
	done
	set_service_value "$service_name" "uci_dependency" ""
}


delete_service() {
	trap 'error_trap delete_service "$*"' EXIT
	local service_name="$1"
	[ -z "$service_name" ] && msg_error "No service given for deletion" && trap "" EXIT && return 1
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
	for service_name in $(get_services | sort_services_by_priority); do
		set_service_value "$service_name" "rank" "$index"
		index=$((index + 1))
	done
}


## @fn move_service_up()
## @brief Verschiebe einen Dienst in der Dienst-Sortierung um eine Stufe nach oben
## @param service_name der zu verschiebende Dienst
## @param service_type der Service-Typ innerhalb derer Mitglieder die Verschiebung stattfinden soll
## @details Für verschiedene Sortier-Modi hat dies verschiedene Auswirkungen:
##   * manual: Verschiebung vor den davorplatzierten Dienst desselben Typs
##   * etx/hop: Reduzierung des Offsets um eins
##   Falls keine Dienst-Typen angegeben sind, bewegt der Dienst sich in der globalen Liste nach unten.
move_service_up() {
	trap 'error_trap move_service_up "$*"' EXIT
	local service_name="$1"
	shift
	local sorting
	local prev_service=
	local current_service
	local temp
	sorting=$(get_service_sorting)
	if [ "$sorting" = "hop" ] || [ "$sorting" = "etx" ]; then
		# reduziere den Offset um eins
		temp=$(get_service_value "$service_name" "offset" 0)
		temp=$(echo "$temp" | awk '{ print $1 - 1 }')
		set_service_value "$service_name" "offset" "$temp"
	elif [ "$sorting" = "manual" ]; then
		for current_service in $(get_services "$@" | sort_services_by_priority); do
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
		msg_info "Warning: [move_service_up] for this sorting method is not implemented: $sorting"
	fi
}


## @fn move_service_down()
## @brief Verschiebe einen Dienst in der Dienst-Sortierung um eine Stufe nach unten
## @param service_name der zu verschiebende Dienst
## @param service_type der Service-Typ innerhalb derer Mitglieder die Verschiebung stattfinden soll
## @details Für verschiedene Sortier-Modi hat dies verschiedene Auswirkungen:
##   * manual: Verschiebung hinter den dahinterliegenden Dienst desselben Typs
##   * etx/hop: Erhöhung des Offsets um eins
##   Falls keine Dienst-Typen angegeben sind, bewegt der Dienst sich in der globalen Liste nach unten.
move_service_down() {
	trap 'error_trap move_service_down "$*"' EXIT
	local service_name="$1"
	shift
	local sorting
	local prev_service=
	local current_service
	local temp
	sorting=$(get_service_sorting)
	if [ "$sorting" = "hop" ] || [ "$sorting" = "etx" ]; then
		# reduziere den Offset um eins
		temp=$(get_service_value "$service_name" "offset" 0)
		temp=$(echo "$temp" | awk '{ print $1 + 1 }')
		set_service_value "$service_name" "offset" "$temp"
	elif [ "$sorting" = "manual" ]; then
		for current_service in $(get_services "$@" | sort_services_by_priority); do
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
		msg_info "Warning: [move_service_down] for this sorting method is not implemented: $sorting"
	fi
}


## @fn move_service_top()
## @brief Verschiebe einen Dienst an die Spitze der Dienst-Sortierung
## @param service_name der zu verschiebende Dienst
## @param service_types ein oder mehrere Dienst-Typen, auf die die Ermittlung der Dienst-Liste begrenzt werden soll (z.B. "gw")
## @details Der Dienst steht anschließend direkt vor dem bisher führenden Dienst der ausgewählten Typen (falls angegeben).
##   Falls keine Dienst-Typen angegeben sind, bewegt der Dienst sich in der globalen Liste an die Spitze.
move_service_top() {
	trap 'error_trap move_service_top "$*"' EXIT
	local service_name="$1"
	shift
	local top_service
	local sorting
	local top_rank
	local new_rank
	local top_distance
	local our_distance
	local current_offset
	local new_offset
	top_service=$(get_services "$@" | sort_services_by_priority | head -1)
	sorting=$(get_service_sorting)
	# kein top-Service oder wir sind bereits ganz oben -> Ende
	if [ -z "$top_service" ] || [ "$top_service" = "$service_name" ]; then
		true
	elif [ "$sorting" = "hop" ] || [ "$sorting" = "etx" ]; then
		top_distance=$(get_distance_with_offset "$top_service" "$sorting")
		our_distance=$(get_distance_with_offset "$service_name" "$sorting")
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
		msg_info "Warning: [move_service_top] for this sorting method is not implemented: $sorting"
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
	local value
	value=$(get_service_value "$service_name" "details" | get_from_key_value_list "$key" ":")
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
	local new_details
	new_details=$(get_service_value "$service_name" "details" | replace_in_key_value_list "$key" ":" "$value")
	set_service_value "$service_name" "details" "$new_details"
	return 0
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
	# Abbruch mit Fehler bei unbekanntem Dienst
	is_existing_service "$service_name" || { trap "" EXIT && return 1; }
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
				msg_error "Unknown service attribute requested: $specification"
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


## @fn get_service_log_filename()
## @brief Ermittle den Namen der Log-Datei für diesen Dienst. Zusätzliche Details (z.B. "openvpn mtu") sind möglich.
## @param service Name eines Dienstes.
## @param other Eine beliebige Anzahl weiterer Parameter ist erlaubt: diese erweitern den typischen Log-Dateinamen für diesen Dienst.
## @details Die Funktion stellt sicher, dass das Verzeichnis der ermittelten Log-Datei anschließend existiert.
get_service_log_filename() {
	trap 'error_trap get_service_log_filename "$*"' EXIT
	local service_name="$1"
	shift
	local full_filename
	local filename="$service_name"
	while [ $# -gt 0 ]; do
		filename="${filename}.$1"
		shift
	done
	full_filename="$SERVICES_LOG_BASE/$(get_safe_filename "$filename").log"
	mkdir -p "$(dirname "$full_filename")"
	echo -n "$full_filename"
}


## @fn get_service_log_content()
## @brief Lies den Inhalt einer Log-Datei für einen Dienst aus.
## @param service Name eines Dienstes.
## @param max_lines maximale Anzahl der auszuliefernden Zeilen (unbegrenzt: 0)
## @param other Eine beliebige Anzahl weiterer Parameter ist erlaubt: diese erweitern den typischen Log-Dateinamen für diesen Dienst.
## @see get_service_log_filename
get_service_log_content() {
	trap 'error_trap get_service_log_content "$*"' EXIT
	local service_name="$1"
	local max_lines="$2"
	shift 2
	local log_filename
	log_filename=$(get_service_log_filename "$service_name" "$@")
	[ -e "$log_filename" ] || return 0
	if [ "$max_lines" = "0" ]; then
		# alle Einträge ausgeben
		cat -
	else
		# nur die letzten Einträge ausliefern
		tail -n "$max_lines"
	fi <"$log_filename"
}


## @fn is_service_routed_via_wan()
## @brief Pruefe ob der Verkehr zum Anbieter des Diensts über ein WAN-Interface verlaufen würde.
## @param service_name der Name des Diensts
## @returns Exitcode == 0, falls das Routing über das WAN-Interface verläuft.
is_service_routed_via_wan() {
	trap 'error_trap is_service_routed_via_wan "$*"' EXIT
	local service_name="$1"
	local host
	local outgoing_device
	local outgoing_zone
	host=$(get_service_value "$service_name" "host")
	outgoing_device=$(get_target_route_interface "$host")
	if is_device_in_zone "$outgoing_device" "$ZONE_WAN"; then
		msg_debug "target '$host' routing through wan device: $outgoing_device"
		return 0
	else
		outgoing_zone=$(get_zone_of_device "$outgoing_device")
		msg_debug "warning: target '$host' is routed via interface '$outgoing_device' (zone '$outgoing_zone') instead of the expected WAN zone ($ZONE_WAN)"
		trap "" EXIT && return 1
	fi
}


_notify_service_success() {
	local service_name="$1"
	set_service_value "$service_name" "status" "true"
	set_service_value "$service_name" "status_fail_counter" ""
	set_service_value "$service_name" "status_timestamp" "$(get_uptime_minutes)"
}


_notify_service_failure() {
	local service_name="$1"
	local max_fail_attempts="$2"
	# erhoehe den Fehlerzaehler
	local fail_counter
	fail_counter=$(( $(get_service_value "$service_name" "status_fail_counter" "0") + 1))
	set_service_value "$service_name" "status_fail_counter" "$fail_counter"
	# Pruefe, ob der Fehlerzaehler gross genug ist, um seinen Status auf "fail" zu setzen.
	if [ "$fail_counter" -ge "$max_fail_attempts" ]; then
		# Die maximale Anzahl von aufeinanderfolgenden fehlgeschlagenen Tests wurde erreicht:
		# markiere ihn als kaputt.
		set_service_value "$service_name" "status" "false"
	elif uci_is_true "$(get_service_value "$service_name" "status")"; then
		# Bisher galt der Dienst als funktionsfaehig - wir setzen ihn auf "neutral" bis
		# die maximale Anzahl aufeinanderfolgender Fehler erreicht ist.
		set_service_value "$service_name" "status" ""
	else
		# Der Test gilt wohl schon als fehlerhaft - das kann so bleiben.
		true
	fi
	set_service_value "$service_name" "status_timestamp" "$(get_uptime_minutes)"
}


## @fn is_trusted_service_list_outdated()
## @brief Ermittle ob mindestens ein Zeitstempel für einen "trusted" Dienst vorhanden ist, der nicht älter
##   als die vorgegebene Aktualisierungsperiode ist.
## @returns Wahr, falls kein Diest mit aktuellem Zeitstempel gefunden wurde.
is_trusted_service_list_outdated() {
	trap 'error_trap is_trusted_service_list_outdated "$*"' EXIT
	local most_recent_timestamp
	most_recent_timestamp=$(get_services \
		| filter_services_by_value "source" "trusted" \
		| pipe_service_attribute "timestamp" | cut -f 2- \
		| sort -n | tail -1)
	# kein Zeitstempel -> dies gilt als "veraltet"
	[ -z "$most_recent_timestamp" ] && return 0
	# der aktuellste Zeitstempel ist zu alt
	is_timestamp_older_minutes "$most_recent_timestamp" "$UPDATE_TRUSTED_SERVICES_PERIOD_MINUTES" && return 0
	trap "" EXIT && return 1
}


retrieve_service_list_url() {
	local url="$1"
	if ! http_request "$url"; then
		if echo "$url" | grep -q '^https://'; then
			# The URL probably uses a certificate signed by the Opennet CA,
			# while "on-certificate" is not installed.
			# Thus we do not emit any warnings.
			true
		else
			msg_info "Failed to retrieve list of services from $url"
		fi
	fi
}


# Beispiel zum Aufruf dieser Funktion: "on-function add_custom_proxy_gw itsuki.on-i.de 1600 udp"
## @fn add_custom_proxy_gw()
## @brief Fuege eine zusätzliches Dienst-Weiterleitung hinzu (proxy-gw).
## @param host der DNS Name des OpenVPN Servers
## @param port der Port des OpenVPN Server (i.d.R. 1600)
## @param protocol udp oder tcp (i.d.R. udp)
add_custom_proxy_gw() {
	local scheme="openvpn"
	local host=$1
	local port=$2
	local protocol=$3
	local priority=5
	local details=""
	local service_name

	service_name=$(notify_service "manual" "proxy-gw" "$scheme" "$host" "$port" "$protocol" "/" "$details")
		set_service_value "$service_name" "priority" "$priority"
		if is_function_available "pick_local_service_relay_port"; then
			pick_local_service_relay_port "$service_name" >/dev/null
		fi
}


## @fn update_trusted_services_list()
## @brief Hole die vertrauenswürdigen Dienste von signierten Opennet-Quellen.
## @details Diese Dienste führen beispielsweise auf UGW-APs zur Konfiguration von Portweiterleitungen
##   ins Internet. Daher sind sie nur aus vertrauenswürdiger Quelle zu akzeptieren (oder manuell).
update_trusted_services_list() {
	local line
	local service_type
	local scheme
	local host
	local port
	local protocol
	local priority
	local details
	local service_name
	local is_proxy
	local service_list
	service_list=$(for url in $SERVICES_LIST_URLS; do retrieve_service_list_url "$url"; done)
	# leeres Ergebnis? Noch keine Internet-Verbindung? Keine Aktualisierung, keine Beraeumung ...
	[ -z "$service_list" ] && msg_info "No trusted services discovered: skipping update." && return
	echo "$service_list" | grep -v "^#" | sed 's/\t\+/\t/g' | while read -r line; do
		service_type=$(echo "$line" | cut -f 1)
		# falls der Dienst-Typ mit "proxy-" beginnt, soll er weitergeleitet werden
		if [ "${service_type#$RELAYABLE_SERVICE_PREFIX}" = "$service_type" ]; then
			# kein Proxy-Dienst
			is_proxy=
		else
			# ein Proxy-Dienst
			is_proxy=1
			# entferne das Praefix
		fi
		scheme=$(echo "$line" | cut -f 2)
		host=$(echo "$line" | cut -f 3)
		port=$(echo "$line" | cut -f 4)
		protocol=$(echo "$line" | cut -f 5)
		priority=$(echo "$line" | cut -f 6)
		details=$(echo "$line" | cut -f 7-)
		service_name=$(notify_service "trusted" "$service_type" "$scheme" "$host" "$port" "$protocol" "/" "$details")
		set_service_value "$service_name" "priority" "$priority"
		if [ -n "$is_proxy" ]; then
			if is_function_available "pick_local_service_relay_port"; then
				pick_local_service_relay_port "$service_name" >/dev/null
			fi
		fi
		true
	done
	# veraltete Dienste entfernen
	local min_timestamp
	min_timestamp=$(($(get_uptime_minutes) - $(get_on_core_default "trusted_service_expire_minutes")))
	# falls die uptime kleiner ist als die Verfallszeit, dann ist ein Test sinnfrei
	if [ "$min_timestamp" -gt 0 ]; then
		for service_name in $(get_services "mesh" | filter_services_by_value "source" "trusted"); do
			timestamp=$(get_service_value "$service_name" "timestamp" 0)
			# Wurde der Service erst vor kurzem aktualisiert? Sonst loeschen ...
			[ "$timestamp" -ge "$min_timestamp" ] || delete_service "$service_name"
		done
	fi
	# aktualisiere DNS- und NTP-Dienste
	apply_changes on-core
}


## @fn run_cyclic_service_tests()
## @brief Durchlaufe alle via STDIN angegebenen Dienste bis mindestens ein Test erfolgreich ist
## @param test_function der Name der zu verwendenden Test-Funktion für einen Dienst (z.B. "verify_vpn_connection")
## @param test_period_minutes Wiederholungsperiode der Dienst-Prüfung
## @param max_fail_attempts Anzahl von Fehlversuchen, bis ein Dienst von "gut" oder "unklar" zu "schlecht" wechselt
## @details Die Diensteanbieter werden in der Reihenfolge ihrer Priorität geprüft.
##   Nach dem ersten Durchlauf dieser Funktion sollte typischerweise der nächstgelegene nutzbare Dienst
##   als funktionierend markiert sein.
##   Falls nach dem Durchlauf aller Dienste keiner positiv getestet wurde (beispielsweise weil alle Zeitstempel zu frisch sind),
##   dann wird in jedem Fall der älteste nicht-funktionsfähige Dienst getestet. Dies minimiert die Ausfallzeit im
##   Falle einer globalen Nicht-Erreichbarkeit aller Dienstenanbieter ohne auf den Ablauf der Test-Periode warten zu müssen.
## @attention Seiteneffekt: die Zustandsinformationen des getesteten Diensts (Status, Test-Zeitstempel) werden verändert.
run_cyclic_service_tests() {
	trap 'error_trap test_openvpn_service_type "$*"' EXIT
	local test_function="$1"
	local test_period_minutes="$2"
	local max_fail_attempts="$3"
	local service_name
	local timestamp
	local status
	for service_name in $(filter_reachable_services \
			| filter_enabled_services \
			| sort_services_by_priority); do
		timestamp=$(get_service_value "$service_name" "status_timestamp" "0")
		status=$(get_service_value "$service_name" "status")
		if [ -z "$status" ] || is_timestamp_older_minutes "$timestamp" "$test_period_minutes"; then
			if "$test_function" "$service_name"; then
				msg_debug "service $service_name successfully tested"
				_notify_service_success "$service_name"
				# wir sind fertig - keine weiteren Tests
				# Da "return" aufgrund der Pipe nicht die gesamte Funktion beenden
				# würde, senden wir stattdessen die Markierung fuer "keine Tests
				# noetig" und beenden die Schleife.
				printf '%s %s\n' "-1" "$service_name"
				break
			else
				msg_debug "failed to verify $service_name"
				_notify_service_failure "$service_name" "$max_fail_attempts"
			fi
		elif uci_is_false "$status"; then
			# Junge "kaputte" Dienste sind potentielle Kandidaten fuer einen vorzeitigen Test, falls
			# ansonsten kein Dienst positiv getestet wurde.
			echo "$timestamp $service_name"
		else
			# funktionsfaehige "alte" Dienste - es gibt nichts fuer sie zu tun
			# Wir sortieren sie nach ganz oben, um bei Existenz eines lauffaehigen Diensts
			# keine unnoetigen Tests von nicht-funktionierenden Hosts durchzufuehren.
			printf '%s %s\n' "-1" "$service_name"
		fi
	done | sort -n | while read -r timestamp service_name; do
		# Mit dem Zeitstempel "-1" sind funktionierende Dienste markiert. Wir brauchen also keine
		# weiteren Tests.
		[ "$timestamp" = "-1" ] && return 0
		# Hier landen wir nur, falls alle defekten Gateways zu jung fuer einen Test waren und
		# gleichzeitig kein Dienst erfolgreich getestet wurde bzw. als erfolgreich gilt.
		# Dies stellt sicher, dass nach einer kurzen Nicht-Erreichbarkeit aller Gateways (z.B. olsr-Ausfall)
		# relativ schnell wieder ein funktionierender Gateway gefunden wird, obwohl alle Test-Zeitstempel noch recht
		# frisch sind.
		msg_debug "there is no service to be tested - thus we pick the service with the oldest test timestamp: $service_name"
		if "$test_function" "$service_name"; then
			_notify_service_success "$service_name"
		else
			_notify_service_failure "$service_name" "$max_fail_attempts"
		fi
		# wir wollen nur genau einen Test durchfuehren
		break
	done
}

# Ende der Doku-Gruppe
## @}
