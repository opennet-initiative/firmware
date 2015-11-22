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
	local target_dir="${IPKG_INSTROOT:-}/usr/sbin/munin-node-plugin.d"
	local source_dir="../../share/munin-plugins-available"
	"${IPKG_INSTROOT:-}/usr/share/munin-plugins-available/$base_plugin" suggest | while read scope; do
		[ -e "$target_dir/${base_plugin}${scope}" ] && continue
		ln -s "$source_dir/$base_plugin" "$target_dir/${base_plugin}${scope}"
	done
}


## @fn remove_suggested_munin_plugin_names()
## @brief Lösche alle spezifischen Symlink-Ziele eines gegebenen Plugins.
remove_suggested_munin_plugin_names() {
	local base_plugin="$1"
	local target_dir="${IPKG_INSTROOT:-}/usr/sbin/munin-node-plugin.d"
	local target
	"${IPKG_INSTROOT:-}/usr/share/munin-plugins-available/$base_plugin" suggest | while read scope; do
		target="$target_dir/${base_plugin}${scope}"
		[ -h "$target" ] && rm "$target"
		true
	done
}

# Ende der Doku-Gruppe
## @}
