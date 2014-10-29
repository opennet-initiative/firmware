
uci_is_true() {
	uci_is_false "$1" && return 1
	return 0
}


uci_is_false() {
	local token=$1
	[ "$token" = "0" -o "$token" = "no" -o "$token" = "off" -o "$token" = "false" ] && return 0
	return 1
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


# Funktion ist vergleichbar mit "uci add_list". Es werden jedoch keine doppelten Einträge erzeugt.
# Somit entfällt die Prüfung auf Vorhandensein des Eintrags.
# Parameter: uci-Pfad
# Parameter: neuer Eintrag
uci_add_list() {
	local uci_path=$1
	local new_item=$2
	local old_items=$(uci_get "$uci_path")
	# ist der Eintrag bereits vorhanden?
	echo " $old_items " | grep -q "\s$new_item\s" && return
	uci add_list "$uci_path=$new_item"
}


uci_del_list() {
	local uci_path=$1
	local remove_item=$2
	local old_values=$(uci_get "$uci_path")
	local value
	uci_delete "$uci_path"
	for value in $old_values; do
		[ "$value" = "$remove_item" ] && continue
		uci add_list "$uci_path=$value"
	done
	return 0
}


uci_delete() {
	uci -q delete "$1" || true
}


# Finde eine uci-Sektion mit gewuenschten Eigenschaften.
# Dies ist hilfreich beim Auffinden von olsrd.@LoadPlugin, sowie firewall-Zonen und aehnlichem.
# Parameter config: Name der uci-config-Datei
# Parameter stype: Typ der Sektion (z.B. "zone" oder "LoadPlugin")
# Parameter Bedingugen:
find_all_uci_sections() {
	local config=$1
	local stype=$2
	local section
	local condition
	shift 2
	uci -X show "$config" | grep "^$config\.[^.]\+\=$stype$" | cut -f 1 -d = | cut -f 2 -d . | while read section; do
		for condition in "$@"; do
			# diese Sektion ueberspringen, falls eine der Bedingungen fehlschlaegt
			uci -X show "$config" | grep -q "^$config\.$section\.$condition$" || continue 2
		done
		# alle Bedingungen trafen zu
		echo "$config.$section"
	done
	return 0
}

find_first_uci_section() {
	find_all_uci_sections "$@" | head -1
}

