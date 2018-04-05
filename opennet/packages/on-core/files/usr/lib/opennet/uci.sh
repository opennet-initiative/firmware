## @defgroup uci UCI
## @brief Hilfreiche Funktionen zum lesenden und schreibenden Zugriff auf die UCI-basierte Konfiguration.
# Beginn der Doku-Gruppe
## @{


uci_is_true() {
	uci_is_false "$1" && trap "" $GUARD_TRAPS && return 1
	return 0
}


uci_is_false() {
	local token="$1"
	# synchron halten mit "uci_to_bool" (lua-Module)
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
	trap "error_trap uci_get '$*'" $GUARD_TRAPS
	local key="$1"
	local default="${2:-}"
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
	trap "error_trap uci_add_list '$*'" $GUARD_TRAPS
	local uci_path="$1"
	local new_item="$2"
	local index
	# ist der Eintrag bereits vorhanden?
	uci_is_in_list "$uci_path" "$new_item" && return 0
	uci add_list "$uci_path=$new_item"
}


## @fn uci_get_list()
## @brief Liefere alle einzelnen Elemente einer UCI-Liste zurück.
## @param uci_path Der UCI-Pfad eines Elements.
## @returns Die Einträge sind zeilenweise voneinander getrennt.
uci_get_list() {
	trap "error_trap uci_get_list '$*'" $GUARD_TRAPS
	local uci_path="$1"
	# falls es den Schlüssel nicht gibt, liefert "uci show" eine Fehlermeldung und Müll - das wollen wir abfangen
	[ -z "$(uci_get "$uci_path")" ] && return 0
	# ansonsten: via "uci show" mit speziellem Trenner abfragen und zeilenweise separieren
	uci -q -d "_=_=_=_=_" show "$uci_path" | cut -f 2- -d = | sed 's/_=_=_=_=_/\n/g' | sed "s/^'\(.*\)'$/\1/"
}


## @fn uci_get_list_index()
## @brief Ermittle die ID eines UCI-Listenelements.
## @param uci_path Der UCI-Pfad der Liste.
## @param value Der Inhalt des zu suchenden Elements.
## @returns Die ID des Listenelements (beginnend bei Null) wird zurückgeliefert.
## @details Falls das Element nicht gefunden wird, ist das Ergebnis leer.
uci_get_list_index() {
	trap "error_trap uci_get_list_index '$*'" $GUARD_TRAPS
	local uci_path="$1"
	local value="$2"
	local current
	local index=0
	for current in $(uci_get_list "$uci_path"); do
		[ "$current" = "$value" ] && echo "$index" && break
		index=$((index + 1))
	done
}


## @fn uci_is_in_list()
## @param uci_path Der UCI-Pfad der Liste.
## @param item Das zu suchende Element.
## @brief Prüfe ob ein Element in einer Liste vorkommt.
uci_is_in_list() {
	trap "error_trap uci_is_in_list '$*'" $GUARD_TRAPS
	local uci_path="$1"
	local value="$2"
	[ -n "$(uci_get_list_index "$uci_path" "$value")" ] && return 0
	trap "" $GUARD_TRAPS && return 1
}


## @fn uci_delete_list()
## @brief Lösche ein Element einer UCI-Liste
## @param uci_path Der UCI-Pfad der Liste.
## @param value Der Inhalt des zu löschenden Elements. Es findet ein Vergleich auf Identität (kein Muster) statt.
## @details Falls das Element nicht existiert, endet die Funktion stillschweigend ohne Fehlermeldung.
uci_delete_list() {
	trap "error_trap uci_delete_list '$*'" $GUARD_TRAPS
	local uci_path="$1"
	local value="$2"
	local index
	index=$(uci_get_list_index "$uci_path" "$value")
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


## @fn filter_uci_show_value_quotes()
## @brief Entferne fuehrende und abschliessende Quotes um die Werte der "uci show"-Ausgabe herum.
## @details Seit Chaos Calmer liefert 'uci show' die Werte (nach dem "=") mit Single-Quotes zurück.
##   Dies ist schön für die Splittung von Listen, aber nervig für unsere Bedingungsprüfung.
##   Wir entfernen die Quotes daher.
## @attention Das Ergebnis ist fuer die Verarbeitung von Listen-Elemente unbrauchbar, da diese separiert
##   von Quotes umgeben sind.
filter_uci_show_value_quotes() {
	sed "s/^\([^=]\+\)='\(.*\)'$/\1=\2/"
}


# Aus Performance-Gruenden brechen wir frueh ab, falls die gewuenschte Anzahl an Ergebnissen erreicht ist.
# Die meisten Anfragen suchen nur einen Treffer ("find_first_uci_section") - daher koennen wir hier viel Zeit sparen.
_find_uci_sections() {
	trap "error_trap _find_uci_sections '$*'" $GUARD_TRAPS
	local max_num="$1"
	local config="$2"
	local stype="$3"
	shift 3
	local counter=0
	local section
	local condition
	# Der Cache beschleunigt den Vorgang wesentlich.
	uci_cache=$(uci -X -q show "$config" | filter_uci_show_value_quotes)
	for section in $(echo "$uci_cache" | grep "^$config\.[^.]\+=$stype$" | cut -f 1 -d = | cut -f 2 -d .); do
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
	trap "error_trap prepare_on_uci_settings '$*'" $GUARD_TRAPS
	local section
	# on-core-Konfiguration erzeugen, falls noetig
	[ -e /etc/config/on-core ] || touch /etc/config/on-core
	for section in settings; do
		uci show | grep -q "^on-core\.${section}\." || uci set "on-core.${section}=$section"
	done
}


## @fn create_uci_section_if_missing
## @brief Prüfe, ob eine definierte UCI-Sektion existiert und lege sie andernfalls an.
## @returns Sektion wurde angelegt (True) oder war bereits vorhanden (false).
create_uci_section_if_missing() {
	trap "error_trap create_uci_section_if_missing '$*'" $GUARD_TRAPS
	local config="$1"
	local stype="$2"
	local key_value
	local uci_prefix
	shift 2
	# liefere "falsch" zurück (Sektion war bereits vorhanden)
	[ -n "$(find_first_uci_section "$config" "$stype" "$@")" ] && { trap "" $GUARD_TRAPS; return 1; }
	# uci-Sektion fehlt -> anlegen
	uci_prefix="$config.$(uci add "$config" "$stype")"
	for key_value in "$@"; do
		uci set "$uci_prefix.$key_value"
	done
	# liefere "wahr" zurück (Sektion wurde angelegt)
	return 0
}

# Ende der Doku-Gruppe
## @}
