# opennet-Funktionen rund um den OLSR-Dienst
# wird durch "on-helper" eingebunden


OLSR_NAMESERVICE_SERVICE_TRIGGER=/usr/sbin/on_nameservice_trigger


# uebertrage die Netzwerke, die derzeit der Zone "opennet" zugeordnet sind, in die olsr-Konfiguration
# Anschliessend wird olsr und die firewall neugestartet.
# Dieses Skript sollte via hotplug bei Aenderungen der Netzwerkkonfiguration ausgefuehrt werden.
update_olsr_interfaces() {
	trap "error_trap update_olsr_interfaces $*" $GUARD_TRAPS
	uci set -q "olsrd.@Interface[0].interface=$(get_zone_interfaces "$ZONE_MESH")"
	apply_changes olsrd
}


# Pruefe das angegebene olsrd-Plugin aktiv ist und aktiviere es, falls dies nicht der Fall sein sollte.
# Das Ergebnis ist die uci-Sektion (z.B. "olsrd.@LoadPlugin[1]") als String.
get_and_enable_olsrd_library_uci_prefix() {
	trap "error_trap get_and_enable_olsrd_library_uci_prefix $*" $GUARD_TRAPS
	local new_section
	local lib_file
	local uci_prefix=
	local library=olsrd_$1
	local current=$(uci show olsrd | grep "^olsrd\.@LoadPlugin\[[0-9]\+\]\.library=$library\.so")
	if [ -n "$current" ]; then
		uci_prefix=$(echo "$current" | cut -f 1 -d = | sed 's/\.library$//')
	else
		lib_file=$(find /usr/lib -type f -name "${library}.*")
		if [ -z "$lib_file" ]; then
			msg_info "FATAL ERROR: Failed to find olsrd '$library' plugin. Some Opennet services will fail."
			trap "" $GUARD_TRAPS && return 1
		fi
		new_section=$(uci add olsrd LoadPlugin)
		uci_prefix=olsrd.${new_section}
		uci set "${uci_prefix}.library=$(basename "$lib_file")"
	fi
	# Plugin aktivieren; Praefix ausgeben
	if [ -n "$uci_prefix" ]; then
		# moeglicherweise vorhandenen 'ignore'-Parameter abschalten
		uci_is_true "$(uci_get "${uci_prefix}.ignore" 0)" && uci set "${uci_prefix}.ignore=0"
		echo "$uci_prefix"
	fi
	return 0
}


enable_ondataservice() {
	trap "error_trap enable_ondataservice $*" $GUARD_TRAPS
	local uci_prefix

	# schon vorhanden? Unberuehrt lassen ...
	[ -n "$(uci show olsrd | grep ondataservice)" ] && return

	# add and activate ondataservice plugin
	uci_prefix=$(get_and_enable_olsrd_library_uci_prefix "ondataservice_light")
	uci set "${uci_prefix}.interval=10800"
	uci set "${uci_prefix}.inc_interval=5"
	uci set "${uci_prefix}.database=/tmp/database.json"
}


enable_nameservice() {
	trap "error_trap enable_nameservice $*" $GUARD_TRAPS
	local current_trigger
	local uci_prefix

	# fuer NTP, DNS und die Gateway-Auswahl benoetigen wir das nameservice-Plugin
	local uci_prefix=$(get_and_enable_olsrd_library_uci_prefix "nameservice")
	if [ -z "$uci_prefix" ]; then
	       msg_info "Failed to find olsrd_nameservice plugin"
	else
		# Option 'services-change-script' setzen
		current_trigger=$(uci_get "${uci_prefix}.services_change_script" || true)
		[ -n "$current_trigger" ] && [ "$current_trigger" != "$OLSR_NAMESERVICE_SERVICE_TRIGGER" ] && \
			msg_info "WARNING: overwriting 'services-change-script' option of olsrd nameservice plugin with custom value. You should place a script below /etc/olsrd/nameservice.d/ instead."
		uci set "${uci_prefix}.services_change_script=$OLSR_NAMESERVICE_SERVICE_TRIGGER"
	fi
}


# Setze die Einstellung MainIP in der olsr-Konfiguration:
# Quelle 1: der erste Parameter
# Quelle 2: on-core.settings.on_id
# Quelle 3: die vorkonfigurierte Standard-IP
# Anschliessend ist "apply_changes olsrd" erforderlich.
olsr_set_main_ip() {
	trap "error_trap olsr_set_main_ip $*" $GUARD_TRAPS
	# Auslesen der aktuellen, bzw. der Standard-IP
	local on_id
	local on_ipschema
	local main_ip
	if [ $# -eq 1 ]; then
		main_ip=$1
	else
		on_id=$(uci_get on-core.settings.on_id "$(get_on_core_default on_id_preset)")
		on_ipschema=$(get_on_core_default on_ipschema)
		main_ip=$(get_on_ip "$on_id" "$on_ipschema" 0)
	fi

	# die Main-IP ist die erste IP dieses Geraets
	uci set "olsrd.@olsrd[0].MainIp=$main_ip"
}


# Ermittle welche olsr-Module konfiguriert sind, ohne dass die Library vorhanden ist.
# Deaktiviere diese Module - fuer ein sauberes boot-Log.
disable_missing_olsr_modules() {
	local libpath=/usr/lib
	local libline
	local libfile
	local uci_prefix
	local ignore
	uci show olsrd | grep "^olsrd.@LoadPlugin\[[0-9]\+\].library=" | while read libline; do
		uci_prefix=$(echo "$libline" | cut -f 1,2 -d .)
		libfile=$(echo "$libline" | cut -f 2- -d =)
		ignore=$(uci_get "${uci_prefix}.ignore")
		[ -n "$ignore" ] && uci_is_true "$ignore" && continue
		if [ ! -e "$libpath/$libfile" ]; then
			msg_info "Disabling missing olsr module '$libfile'"
			uci set "${uci_prefix}.ignore=1"
		fi
	done
	apply_changes olsrd
}


# erzeuge und konfiguriere separate Routing-Tabellen für die olsr-Einträge
olsr_set_routing_tables() {
	local rt_common=$1
	local rt_default=$2
	local rt_common_id=$(uci_get "olsrd.@olsrd[0].RtTable")
	local rt_default_id=$(uci_get "olsrd.@olsrd[0].RtTableDefault")
	if [ -z "$rt_common_id" ]; then
		rt_common_id=$(get_or_add_routing_table "$rt_common")
		uci set "olsrd.@olsrd[0].RtTable=$rt_common_id"
	fi
	if [ -z "$rt_default_id" ]; then
		rt_default_id=$(get_or_add_routing_table "$rt_default")
		uci set "olsrd.@olsrd[0].RtTableDefault=$rt_default_id"
	fi
	apply_changes olsrd
}

