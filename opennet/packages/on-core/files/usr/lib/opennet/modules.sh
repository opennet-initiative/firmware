## @defgroup modules Module
## @brief Verwaltung der Opennet-Module für verschiedene Funktionen/Rollen
# Beginn der Doku-Gruppe
## @{

# Basis-URL für Opennet-Paketinstallationen
ON_OPKG_REPOSITORY_URL_PREFIX_OPENNET="http://downloads.on/openwrt"
ON_OPKG_REPOSITORY_URL_PREFIX_INTERNET="http://downloads.opennet-initiative.de/openwrt"
# temporäre Datei für Installation von Opennet-Paketen
ON_OPKG_CONF_PATH="${IPKG_INSTROOT:-}/tmp/opkg-opennet.conf"


## @fn is_on_module_installed_and_enabled()
## @brief Pruefe ob ein Modul sowohl installiert, als auch aktiv ist.
## @param module Eins der Opennet-Pakete (siehe 'get_on_modules').
## @details Die Aktivierung eines Modules wird anhand der uci-Einstellung "${module}.settings.enabled" geprueft.
##   Der Standardwert ist "false" (ausgeschaltet).
is_on_module_installed_and_enabled() {
	trap "error_trap is_on_module_installed_and_enabled '$*'" $GUARD_TRAPS
	local module="$1"
	is_package_installed "$module" && _is_on_module_enabled "$module" && return 0
	trap "" $GUARD_TRAPS && return 1
}


_is_on_module_enabled() {
	local module="$1"
	uci_is_in_list "on-core.modules.enabled" "$module" && return 0
	trap "" $GUARD_TRAPS && return 1
}


## @fn enable_on_module()
## @brief Aktiviere ein Opennet-Modul
## @param module Eins der Opennet-Pakete (siehe 'get_on_modules').
enable_on_module() {
	trap "error_trap enable_on_module '$*'" $GUARD_TRAPS
	local module="$1"
	_is_on_module_enabled "$module" && return 0
	[ -z "$(uci_get "on-core.modules")" ] && uci set "on-core.modules=modules"
	uci_add_list "on-core.modules.enabled" "$module"
	apply_changes "on-core" "$module"
}


## @fn disable_on_module()
## @brief Deaktiviere ein Opennet-Modul
## @param module Eins der Opennet-Pakete (siehe 'get_on_modules').
disable_on_module() {
	trap "error_trap disable_on_module '$*'" $GUARD_TRAPS
	local module="$1"
	_is_on_module_enabled "$module" || return 0
	uci_delete_list "on-core.modules.enabled" "$module"
	apply_changes "on-core" "$module"
}


## @fn get_on_modules()
## @brief Liefere die Namen aller bekannten Opennet-Module zeilenweise getrennt zurück.
## @details Die Liste kann in der Datei ON_CORE_DEFAULTS_FILE angepasst werden.
get_on_modules() {
	# zeilenweise splitten (wir erwarten nur kleine Buchstaben im Namen)
	get_on_core_default "on_modules" | sed 's/[^a-z-]/\n/g' | grep -v "^$"
}


## @fn was_on_module_installed_before()
## @brief Prüfe ob ein Modul "früher" (vor der letzten manuellen Änderung durch den Benutzer) installiert war.
## @details Diese Prüfung ist hilfreich für die Auswahl von nachträglich zu installierenden Paketen.
was_on_module_installed_before() {
	local module="$1"
	uci_is_in_list "on-core.modules.installed" "$module" && return 0
	trap "" $GUARD_TRAPS && return 1
}


## @fn install_from_opennet_repository()
## @param packages Ein oder mehrere zu installierende Software-Pakete
## @returns Eventuelle Fehlermeldungen werden auf die Standardausgabe geschrieben. Der Exitcode ist immer Null.
## @brief Installiere ein Paket aus den Opennet-Repositories.
## @details Für die Installation von Opennet-relevanten Paketen wird eine separate opkg.conf-Datei verwendet.
##   Alle nicht-opennet-relevanten Pakete sollten - wie gewohnt - aus den openwrt-Repositories heraus installiert
##   werden, da deren Paket-Liste umfassender ist.
##   Die opkg.conf wird im tmpfs erzeugt, falls sie noch nicht vorhanden ist. Eventuelle manuelle Nachkorrekturen
##   bleiben also bis zum nächsten Reboot erhalten.
install_from_opennet_repository() {
	trap "error_trap install_from_opennet_repository '$*'" $GUARD_TRAPS
	local package
	_run_opennet_opkg "update" && _run_opennet_opkg "install" "$@"
	for package in "$@"; do
		if get_on_modules | grep -qwF "$package"; then
			# Eventuell schlug die Installation fehl?
			is_package_installed "$package" || continue
			# Falls es ein opennet-Modul ist, dann aktiviere es automatisch nach der Installation.
			# Dies dürfte für den Nutzer am wenigsten überraschend sein.
			enable_on_module "$package"
		fi
	done
	# anschließend speichern wir den aktuellen Zustand, falls _alle_ Pakete installiert wurden
	for package in "$@"; do
		# Paket fehlt? aktuelle Liste nicht speichern, sondern einfach abbrechen
		is_package_installed "$package" || return 0
	done
	save_on_modules_list
}


## @fn remove_opennet_module()
## @param module Name des oder der zu entfernenden Module
remove_opennet_modules() {
	local log_file=$(get_custom_log_filename "opkg_opennet")
	_run_opennet_opkg --autoremove remove "$@"
	save_on_modules_list
}


# Ausführung eines opkg-Kommnados mit der opennet-Repository-Konfiguration und minimaler Ausgabe (nur Fehler) auf stdout.
_run_opennet_opkg() {
	trap "error_trap _run_opennet_opkg '$*'" $GUARD_TRAPS
	# erzeuge Konfiguration, falls sie noch nicht vorhanden ist
	[ -e "$ON_OPKG_CONF_PATH" ] || generate_opennet_opkg_config >"$ON_OPKG_CONF_PATH"
	local log_file=$(get_custom_log_filename "opkg_opennet")
	# Vor der opkg-Ausführung müssen wir das Verzeichnis /etc/opkg verdecken, da opkg fehlerhafterweise
	# auch bei Verwendung von "--conf" die üblichen Orte nach Konfigurationsdateien durchsucht.
	# TODO: opkg-Bug upstream berichten
	mount -t tmpfs -o size=32k tmpfs /etc/opkg
	# opkg ausfuehren und dabei die angegebene Fehlermeldung ignorieren (typisch fuer Paket-Installation nach Upgrade)
	opkg --verbosity=1 --conf "$ON_OPKG_CONF_PATH" "$@" >>"$log_file" 2>&1 \
		| grep -vF "resolve_conffiles: Existing conffile /etc/config/openvpn is different from the conffile in the new package. The new conffile will be placed at /etc/config/openvpn-opkg." \
		| grep -v "^Collected errors:$" \
		|| true
	umount /etc/opkg
}


## @fn save_on_modules_list()
## @brief Speichere die aktuelle Liste der installierten opennet-Module in der uci-Konfiguration.
## @details Nach einer Aktualisierung ermöglicht diese Sicherung die Nachinstallation fehlender Pakete.
save_on_modules_list() {
	local modname
	[ -z "$(uci_get "on-core.modules")" ] && uci set "on-core.modules=modules"
	get_on_modules | while read modname; do
		is_package_installed "$modname" \
			&& uci_add_list "on-core.modules.installed" "$modname" \
			|| uci_delete_list "on-core.modules.installed" "$modname"
	done
	apply_changes on-core
}


## @fn clear_cache_opennet_opkg()
## @brief Lösche die eventuell vorhandene opennet-opkg-Konfiguration (z.B. nach einem Update).
clear_cache_opennet_opkg() {
	rm -f "$ON_OPKG_CONF_PATH"
}


## @fn get_default_opennet_opkg_repository_url()
## @param target_zone Entweder "internet" oder "opennet".
## @brief Ermittle die automatisch ermittelte URL für die Nachinstallation von Paketen.
## @returns Liefert die Basis-URL bis einschließlich "/packages". Lediglich der Feed-Name ist anzuhängen.
get_default_opennet_opkg_repository_url() {
	trap "error_trap get_default_opennet_opkg_repository_url '$*'" $GUARD_TRAPS
	local target_zone="$1"
	local prefix
	if [ "$target_zone" = "opennet" ]; then
		prefix="$ON_OPKG_REPOSITORY_URL_PREFIX_OPENNET"
	elif [ "$target_zone" = "internet" ]; then
		prefix="$ON_OPKG_REPOSITORY_URL_PREFIX_INTERNET"
	else
		msg_info "Invalid opkg repository target zone requested: $target_zone"
		# sinnvolle Rueckfalloption verwenden
		prefix="$ON_OPKG_REPOSITORY_URL_PREFIX_OPENNET"
	fi
	# ermittle die Firmware-Repository-URL
	local firmware_version
	firmware_version=$(get_on_firmware_version)
	# leere Versionsnummer? Damit können wir nichts anfangen.
	[ -z "$firmware_version" ] && msg_error "Failed to retrieve opennet firmware version for opkg repository URL" && return 0
	# snapshots erkennen wir aktuell daran, dass auch Buchstaben in der Versionsnummer vorkommen
	local version_path
	if echo "$firmware_version" | grep -q "[a-zA-Z]"; then
		# ein Buchstabe wurde entdeckt: unstable
		version_path="testing/$firmware_version"
	else
		# kein Buchstabe wurde entdeckt: stable
		# wir schneiden alles ab dem ersten Bindestrich ab
		version_path="stable/$(echo "$firmware_version" | cut -f 1 -d -)"
	fi
	# Hole "DISTRIB_TARGET" und entferne potentielle "/generic"-Suffixe (z.B. ar71xx und x86),
	# da wir dies in unserem Repository nicht abbilden.
	local arch_path
	arch_path=$(. /etc/openwrt_release; echo "$DISTRIB_TARGET" | sed 's#/generic$##')
	echo "$prefix/$version_path/$arch_path/packages"
}


## @fn get_configured_opennet_opkg_repository_url()
## @brief Ermittle die aktuell konfigurierte Repository-URL.
get_configured_opennet_opkg_repository_url() {
	local prefix
	prefix=$(uci_get "on-core.modules.repository_url")
	[ -n "$prefix" ] && echo "$prefix" || get_default_opennet_opkg_repository_url "opennet"
}


## @fn set_configured_opennet_opkg_repository_url()
## @param repo_url Die neue Repository-URL (bis einschliesslich "/packages").
## @brief Ändere die aktuell konfigurierte Repository-URL.
## @details Die URL wird via uci gespeichert. Falls sie identisch mit der Standard-URL ist, wird die Einstellung gelöscht.
set_configured_opennet_opkg_repository_url() {
	local repo_url="$1"
	if [ -z "$repo_url" ] || [ "$repo_url" = "$(get_default_opennet_opkg_repository_url "opennet")" ]; then
		# Standard-Wert: loeschen
		uci_delete "on-core.modules.repository_url"
	else
		uci set "on-core.modules.repository_url=$repo_url"
	fi
	clear_cache_opennet_opkg
}


## @fn generate_opennet_opkg_config()
## @brief Liefere den Inhalt einer opkg.conf für das Opennet-Paket-Repository zurück.
## @details Die aktuelle Version wird aus dem openwrt-Versionsstring gelesen.
generate_opennet_opkg_config() {
	trap "error_trap generate_opennet_opkg_config '$*'" $GUARD_TRAPS
	local repository_url="$(get_configured_opennet_opkg_repository_url)"
	# schreibe den Inahlt der neuen OPKG-Konfiguration
	echo "dest root /"
	echo "dest ram /tmp"
	echo "lists_dir ext /var/opkg-lists-opennet"
	echo "option overlay_root /overlay"
	echo
	local feed
	for feed in base packages routing telephony luci opennet; do
		echo "src/gz on_$feed $repository_url/$feed"
	done
}


## @fn is_package_installed()
## @brief Prüfe, ob ein opkg-Paket installiert ist.
## @param package Name des Pakets
is_package_installed() {
	local package="$1"
	# Korrekte Prüfung: via "opkg list-installed" - leider erzeugt sie locking-Fehlermeldung
	# bei parallelen Abläufen (z.B. Status-Seite).
	#opkg list-installed | grep -q -w "^$package" && return 0
	# schneller als via opkg
	[ -e "${IPKG_INSTROOT:-}/usr/lib/opkg/info/${package}.control" ] && return 0
	trap "" $GUARD_TRAPS && return 1
}


## @fn on_opkg_postinst_default()
## @brief Übliche Nachbereitung einer on-Paket-Installation.
## @details Caches löschen, uci-defaults anwenden, on-core-Bootskript ausführen
on_opkg_postinst_default() {
	# Reset des Luci-Cache und Shell-Cache
	clear_caches
	# Paket-Initialisierungen durchfuehren, falls wir in einem echten System sind.
	# In der Paket-Bau-Phase funktioniert die untenstehende Aktion nicht, da eine
	# Datei fehlt, die in der /etc/init.d/boot geladen wird.
	if [ -z "${IPKG_INSTROOT:-}" ]; then
		msg_info "Applying uci-defaults after package installation"
		# Die Angabe von IPKG_INSTROOT ist hier muessig - aber vielleicht
		# koennen wir die obige Bedingung irgendwann entfernen.
		(
			# der Rest sollte ohne Vorsicht stattfinden
			set +eu
			. "${IPKG_INSTROOT:-}/etc/init.d/boot"
			uci_apply_defaults
			# Boot-Skript aktivieren und ausführen (falls noch nicht geschehen)
			/etc/init.d/on-core enable 2>/dev/null || true
			/etc/init.d/on-core start
			set -eu
		)
	fi
	clean_luci_restart
}


## @fn on_opkg_postrm_default()
## @brief Übliche Nachbereitung einer on-Paket-Entfernung
## @details Caches löschen
on_opkg_postrm_default() {
	clear_caches
	clean_luci_restart
}

# Ende der Doku-Gruppe
## @}
