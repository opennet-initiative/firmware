## @defgroup monitoring Monitoring
## @brief Ermittlung statistischer Daten in Form von munin-Plugins
# Beginn der Doku-Gruppe
## @{


## @fn enable_munin_plugins()
## @brief Aktiviere die Plugin-Unterstützung von muninlite durch Patchen des muninlite-Skripts.
## @details Die Plugin-Unterstützung von muninlite wird durch Hinzufügen des Token 'plugindir_' zu
##   der Variable 'PLUGINS' umgesetzt. Dies ist ein kleines bisschen hässlich :(
enable_munin_plugins() {
	local target="${IPKG_INSTROOT:-}/usr/sbin/munin-node"
	# nicht installiert?
	[ -e "$target" ] || return 0
	# bereits konfiguriert?
	grep -q "^PLUGINS=.*plugindir_" "$target" && return 0
	# "plugindir_" einfuegen
	sed -i "/^PLUGINS=\".*\"$/s/^PLUGINS=\"/PLUGINS=\"plugindir_ /" "$target"
}


## @fn update_munin_service_state()
## @brief Munin-Dienst an- oder abschalten - je nach Modul-Zustand.
update_monitoring_state() {
	if is_on_module_installed_and_enabled "on-monitoring"; then
		/etc/init.d/xinetd enable || true
		/etc/init.d/xinetd start || true
	else
		disable_monitoring
	fi
}


## @fn disable_monitoring()
## @brief Monitoring abschalten
disable_monitoring() {
	/etc/init.d/xinetd disable || true
	/etc/init.d/xinetd stop || true
}


## @fn enable_suggested_munin_plugin_names()
## @brief Ermittle die von einem Plugin empfohlenen Ziele und aktiviere sie in Form von Symlinks.
## @details Dies ist eine Umsetzung der munin-typischen Selbsterkennung von Plugin-Zielen.
enable_suggested_munin_plugin_names() {
	local base_plugin="$1"
	local plugin_file="${IPKG_INSTROOT:-}/usr/share/munin-plugins-available/$base_plugin"
	local target_dir="${IPKG_INSTROOT:-}/usr/sbin/munin-node-plugin.d"
	local source_dir="../../share/munin-plugins-available"
	# wird der "suggest"-Mechanismus unterstuetzt?
	local capabilities
	capabilities=$(grep "#%#[[:space:]]\+capabilities[[:space:]]*=" "$plugin_file" | cut -f 2 -d "=")
	# keine Ausfuehrung ohne "suggest"-Faehigkeit
	echo "$capabilities" | grep -qw "suggest" || return 0
	"$plugin_file" suggest | while read -r scope; do
		[ -z "$scope" ] && continue
		[ -e "$target_dir/${base_plugin}${scope}" ] && continue
		ln -s "$source_dir/$base_plugin" "$target_dir/${base_plugin}${scope}"
	done
}


disable_munin_plugin() {
	local base_plugin="$1"
	local active_plugin_dir="${IPKG_INSTROOT:-}/usr/sbin/munin-node-plugin.d/"
	[ -d "$active_plugin_dir" ] || return 0
	find "$active_plugin_dir" -type l -name "$1*" -delete
}


## @fn remove_suggested_munin_plugin_names()
## @brief Lösche alle spezifischen Symlink-Ziele eines gegebenen Plugins.
remove_suggested_munin_plugin_names() {
	local base_plugin="$1"
	local target_dir="${IPKG_INSTROOT:-}/usr/sbin/munin-node-plugin.d"
	local target
	"${IPKG_INSTROOT:-}/usr/share/munin-plugins-available/$base_plugin" suggest | while read -r scope; do
		target="$target_dir/${base_plugin}${scope}"
		[ -h "$target" ] && rm "$target"
		true
	done
}


_prepare_on_monitoring_plugin_settings() {
	local plugin="$1"
	[ -e "/etc/config/on-monitoring" ] || touch "/etc/config/on-monitoring"
	[ -n "$(uci_get "on-monitoring.plugin_$plugin")" ] || uci set "on-monitoring.plugin_${plugin}=plugin"
}


## @fn add_monitoring_multiping_host()
## @param host Ziel-Host (IP oder Hostname)
## @param label Dauerhaftes Label des Ping-Ziels (dies ermoeglicht die Ersetzung oder Loeschung)
## @brief Füge einen via multiping zu überwachenden Host hinzu. Duplikate werden entfernt.
add_monitoring_multiping_host() {
	local host="$1"
	local label="${2:-}"
	local new_spec
	[ -n "$label" ] && new_spec="$host=$label" || new_spec="$host"
	local old_spec
	_prepare_on_monitoring_plugin_settings "multiping"
	for old_spec in $(uci -q get "on-monitoring.plugin_multiping.hosts"); do
		# alter Eintrag ist vorhanden und korrekt - es ist nichts zu tun
		[ "$old_spec" = "$new_spec" ] && return 0
		# Eintrag mit identischem Label ist vorhanden - Eintrag ersetzen
		if [ -n "$label" ] && [ "$label" = "$(echo "$old_spec" | cut -f 2- -d "=")" ]; then
			uci -q del_list "on-monitoring.plugin_multiping.hosts=$old_spec"
			break
		fi
	done
	uci add_list "on-monitoring.plugin_multiping.hosts=$new_spec"
	uci commit "on-monitoring"
}


## @fn del_monitoring_multiping_host_by_label()
## @param label Dauerhaftes Label des Ping-Ziels
## @brief Lösche den multiping-Eintrag mit diesem Namen.
## @returns Keine Rückgabe. Die Funktion verläuft immer erfolgreich, auch wenn der Host nicht gefunden wurde.
del_monitoring_multiping_host_by_label() {
	local label="$1"
	local host_spec
	for host_spec in $(uci -q get "on-monitoring.plugin_multiping.hosts"); do
		[ "$label" = "$(echo "$host_spec" | cut -f 2- -d "=")" ] || continue
		uci -q del_list "on-monitoring.plugin_multiping.hosts=$host_spec"
	done
	uci commit "on-monitoring"
}

# Ende der Doku-Gruppe
## @}
