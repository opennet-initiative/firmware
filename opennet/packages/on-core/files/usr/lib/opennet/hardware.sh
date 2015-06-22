## @defgroup on-hardware Hardware-Einstellungen
# Beginn der Doku-Gruppe
## @{


## @fn get_machine_type()
## @brief Ermittle die Machine-Bezeichnung (siehe /proc/cpuinfo)
get_machine_type() {
	grep "^machine" /proc/cpuinfo | cut -f 2- -d ":" | sed 's/^ *//'
}


## @fn _get_or_set_gpio()
## @brief Setze oder lese ein GPIO-Pin.
## @param pin Die Nummer des GPIO-Pins.
## @param value Der zu setzende Wert (0/1). Falls der Wert leer ist, wird stattdessen der aktuelle
##   Zustand (an/aus) als Exitcode zurueckgeliefert.
_get_or_set_gpio() {
	trap "" $GUARD_TRAPS
	local pin="$1"
	local value="${2:-}"
	local gpio_path="/sys/class/gpio/gpio$pin"
	# setup
	if [ ! -d "$gpio_path" ]; then
		echo "$pin" >/sys/class/gpio/export
		# wir muessen nach der Initialisierung kurz warten
		sleep 1
		echo out >"$gpio_path/direction"
		sleep 1
	fi
	if [ -n "$value" ]; then
		# neuen Zustand setzen
		echo "$value" >"$gpio_path/value"
	else
		local state=$(cat "$gpio_path/value")
		# aktuellen Zustand zurueckliefern
		[ "$state" = "1" ] && return 0 || return 1
	fi
}


## @fn _get_poe_passthrough_function()
## @brief Ermittle die fuer die Hardware geeignete POE-Passthrough-Funktion (zum Lesen und Setzen des Zustands).
_get_poe_passthrough_function() {
	local machine_type=$(get_machine_type)
	if [ "$machine_type" = "TP-LINK CPE210/220/510/520" ]; then
		echo "_get_or_set_gpio 20"
	elif [ "$machine_type" = "Ubiquiti Nanostation M" ]; then
		# Nanostation XM: loco oder HP
		# leider koennen wir sie nicht unterscheiden
		echo "_get_or_set_gpio 8"
	elif [ "$machine_type" = "Ubiquiti Nanostation M XW" ]; then
		# die HP-Variante (anstelle von "Ubiquiti Loco M XW")
		echo "_get_or_set_gpio 2"
	else
		# keine POE-Unterstuetzung
		true
	fi
}


## @fn has_poe_passthrough_support()
## @brief Pruefe, ob die aktuelle Hardware POE-Passthrough unterstuetzt.
## @details Bei der Ubiquiti Nanostation M2 und M5 (XM) kann die loco-Variante nicht von der
##   HP-Variante unterschieden werden.
has_poe_passthrough_support() {
	trap "error_trap has_poe_passthrough_support '$*'" $GUARD_TRAPS
	local funcname=$(_get_poe_passthrough_function)
	[ -z "$funcname" ] && trap "" $GUARD_TRAPS && return 1
	return 0
}


## @fn get_poe_passthrough_state()
## @brief Ermittle den aktuellen Zustand (wahr=an, falsch=aus) der POE-Weiterleitung.
get_poe_passthrough_state() {
	trap "error_trap get_poe_passthrough_state '$*'" $GUARD_TRAPS
	local funcname=$(_get_poe_passthrough_function)
	[ -z "$funcname" ] && msg_error "POE passthrough is not supported for this device." && return 0
	$funcname
}


## @fn disable_poe_passthrough()
## @brief Schalte die POE-Weiterleitung aus.
disable_poe_passthrough() {
	trap "error_trap disable_poe_passthrough '$*'" $GUARD_TRAPS
	local funcname=$(_get_poe_passthrough_function)
	[ -z "$funcname" ] && msg_error "POE passthrough is not supported for this device." && return 0
	$funcname 0
}


## @fn enable_poe_passthrough()
## @brief Schalte die POE-Weiterleitung an.
enable_poe_passthrough() {
	trap "error_trap enable_poe_passthrough '$*'" $GUARD_TRAPS
	local funcname=$(_get_poe_passthrough_function)
	[ -z "$funcname" ] && msg_error "POE passthrough is not supported for this device." && return 0
	$funcname 1
}

# Ende der Doku-Gruppe
## @}
