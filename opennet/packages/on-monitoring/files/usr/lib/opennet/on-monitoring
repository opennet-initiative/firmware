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

# Ende der Doku-Gruppe
## @}
