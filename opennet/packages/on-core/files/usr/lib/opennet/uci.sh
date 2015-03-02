## @defgroup uci UCI
## @brief Hilfreiche Funktionen zum lesenden und schreibenden Zugriff auf die UCI-basierte Konfiguration.
# Beginn der Doku-Gruppe
## @{


uci_is_true() {
	uci_is_false "$1" && trap "" $GUARD_TRAPS && return 1
	return 0
}


uci_is_false() {
	local token=$1
	[ "$token" = "0" -o "$token" = "no" -o "$token" = "n" -o "$token" = "off" -o "$token" = "false" ] && return 0
	trap "" $GUARD_TRAPS && return 1
}


# "uci -q get ..." endet mit einem Fehlercode falls das Objekt nicht existiert
# Dies erschwert bei strikter Fehlerpruefung (set -e) die Abfrage von uci-Werten.
# Die Funktion "uci_get" liefert bei fehlenden Objekten einen leeren String zurueck
# oder den gegebenen Standardwert zurueck.
# Der Exitcode signalisiert immer Erfolg.
# Syntax:
#   uci_get firewall.zone_free.masq 1
# Der abschließende Standardwert (zweiter Parameter) ist optional.
uci_get() {
	local key=$1
	local default=${2:-}
	if uci -q get "$key"; then
		return 0
	else
		[ -n "$default" ] && echo "$default"
		return 0
	fi
}


## @fn uci_add_list()
## @brief Füge einen neuen Wert zu einer UCI-Liste hinzu und achte dabei auf Einmaligkeit.
## @param uci_path Der UCI-Pfad des Listenelements.
## @param new_item Der neue Wert, der zur Liste hinzugefügt werden soll.
## @details Die Funktion ist vergleichbar mit "uci add_list". Es werden jedoch keine doppelten Einträge erzeugt.
##   Somit entfällt die Prüfung auf Vorhandensein des Eintrags.
uci_add_list() {
	local uci_path="$1"
	local new_item="$2"
	# ist der Eintrag bereits vorhanden?
	local index=$(uci_get_list_index "$uci_path" "$new_item")
	# schon vorhanden? Fertig ...
	[ -n "$index" ] && return 0
	uci add_list "$uci_path=$new_item"
}


## @fn uci_get_list()
## @brief Liefere alle einzelenen Elemente einer UCI-Liste zurück.
## @param uci_path Der UCI-Pfad eines Elements.
## @returns Die Einträge sind zeilenweise voneinander getrennt.
uci_get_list() {
	local uci_path="$1"
	uci show -d "_=_=_=_=_" "$uci_path" | cut -f 2- -d = | sed 's/_=_=_=_=_/\n/g'
}


## @fn uci_get_list_index()
## @brief Ermittle die ID eines UCI-Listenelements.
## @param uci_path Der UCI-Pfad der Liste.
## @param value Der Inhalt des zu suchenden Elements.
## @returns Die ID des Listenelements (beginnend bei Null) wird zurückgeliefert.
## @details Falls das Element nicht gefunden wird, ist das Ergebnis leer.
uci_get_list_index() {
	local uci_path="$1"
	local value="$2"
	local current
	local index=0
	uci_get_list "$uci_path" | while read current; do
		[ "$current" = "$value" ] && echo "$index" && return 0
		: $((index++))
	done
	return 0
}


## @fn uci_delete_list()
## @brief Lösche ein Element einer UCI-Liste
## @param uci_path Der UCI-Pfad der Liste.
## @param value Der Inhalt des zu löschenden Elements. Es findet ein Vergleich auf Identität (kein Muster) statt.
## @details Falls das Element nicht existiert, endet die Funktion stillschweigend ohne Fehlermeldung.
uci_delete_list() {
	local uci_path="$1"
	local value="$2"
	local index=$(uci_get_list_index "$uci_path" "$value")
	[ -n "$index" ] && uci_delete "${uci_path}=${index}"
	return 0
}


## @fn uci_delete()
## @brief Lösche ein UCI-Element.
## @param uci_path Der UCI-Pfad des Elements.
## @details Keine Fehlermeldung, falls das Element nicht existiert.
uci_delete() {
	local uci_path="$1"
	uci -q delete "$uci_path" || true
}


# Finde eine uci-Sektion mit gewuenschten Eigenschaften.
# Dies ist hilfreich beim Auffinden von olsrd.@LoadPlugin, sowie firewall-Zonen und aehnlichem.
# Parameter config: Name der uci-config-Datei
# Parameter stype: Typ der Sektion (z.B. "zone" oder "LoadPlugin")
# Parameter Bedingugen:
find_all_uci_sections() {
	_find_uci_sections 0 "$@"
}


# Ermittle den ersten Treffer einer uci-Sektionssuche (siehe find_all_uci_sections)
find_first_uci_section() {
	_find_uci_sections 1 "$@"
}


# Aus Performance-Gruenden brechen wir frueh ab, falls die gewuenschte Anzahl an Ergebnissen erreicht ist.
# Die meisten Anfragen suchen nur einen Treffen ("find_first_uci_section") - daher koennen wir hier viel Zeit sparen.
_find_uci_sections() {
	local max_num=$1
	local config=$2
	local stype=$3
	shift 3
	local counter=0
	local section
	local condition
	# dieser Cache beschleunigt den Vorgang wesentlich
	local uci_cache=$(uci -X show "$config")
	echo "$uci_cache" | grep "^$config\.[^.]\+=$stype$" | cut -f 1 -d = | cut -f 2 -d . | while read section; do
		for condition in "$@"; do
			# diese Sektion ueberspringen, falls eine der Bedingungen fehlschlaegt
			echo "$uci_cache" | grep -q "^$config\.$section\.$condition$" || continue 2
		done
		# alle Bedingungen trafen zu
		echo "$config.$section"
		: $((counter++))
		[ "$max_num" = 0 ] && continue
		[ "$counter" -ge "$max_num" ] && break
	done | sort
	return 0
}


# Erzeuge die notwendigen on-core-Einstellungen fuer uci, falls sie noch nicht existieren.
# Jede Funktion, die im on-core-Namensraum Einstellungen schreiben moechte, moege diese
# Funktion zuvor aufrufen.
prepare_on_uci_settings() {
	local section
	# on-core-Konfiguration erzeugen, falls noetig
	[ -e /etc/config/on-core ] || touch /etc/config/on-core
	for section in settings; do
		uci show | grep -q "^on-core\.${section}\." || uci set "on-core.${section}=$section"
	done
}

# Ende der Doku-Gruppe
## @}
