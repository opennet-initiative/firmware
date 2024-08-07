## @defgroup modules Module
## @brief Verwaltung der Opennet-Module für verschiedene Funktionen/Rollen
# Beginn der Doku-Gruppe
## @{

# Basis-URL für Opennet-Paketinstallationen
ON_OPKG_REPOSITORY_URL_PREFIX="https://downloads.opennet-initiative.de/openwrt"
# temporäre Datei für Installation von Opennet-Paketen
ON_OPKG_CONF_PATH="${IPKG_INSTROOT:-}/tmp/opkg-opennet.conf"
# shellcheck disable=SC2034
DEFAULT_MODULES_ENABLED="on-olsr2"


# Erzeuge die uci-Sektion "on-core.modules" und aktiviere Standard-Module.
_prepare_on_modules() {
	[ -n "$(uci_get "on-core.modules")" ] && return
	uci set "on-core.modules=modules"
}


## @fn is_on_module_installed_and_enabled()
## @brief Pruefe ob ein Opennet-Modul sowohl installiert, als auch aktiviert ist.
## @param module Name des Opennet-Paketes (siehe 'get_on_modules').
## @details Die Aktivierung eines Modules wird anhand der uci-Einstellung "${module}.settings.enabled" geprueft.
##   Der Standardwert ist "false" (ausgeschaltet).
is_on_module_installed_and_enabled() {
	trap 'error_trap is_on_module_installed_and_enabled "$*"' EXIT
	local module="$1"
	_prepare_on_modules
	is_on_module_installed "$module" && _is_on_module_enabled "$module" && return 0
	trap "" EXIT && return 1
}


_is_on_module_enabled() {
	local module="$1"
	_prepare_on_modules
	uci_is_in_list "on-core.modules.enabled" "$module" && return 0
	trap "" EXIT && return 1
}


## @fn is_on_module_installed()
## @brief Pruefe ob ein Opennet-Modul installiert ist.
## @param module Name des Opennet-Paketes (siehe 'get_on_modules').
is_on_module_installed() {
	local module="$1"
	_prepare_on_modules
	is_package_installed "$module" && return 0
	trap "" EXIT && return 1
}


## @fn enable_on_module()
## @brief Aktiviere ein Opennet-Modul
## @param module Name des Opennet-Paketes (siehe 'get_on_modules').
enable_on_module() {
	trap 'error_trap enable_on_module "$*"' EXIT
	local module="$1"
	_prepare_on_modules
	warn_if_unknown_module "$module"
	warn_if_not_installed_module "$module"
	uci_add_list "on-core.modules.enabled" "$module"
	apply_changes "on-core" "$module"
}


## @fn disable_on_module()
## @brief Deaktiviere ein Opennet-Modul
## @param module Name des Opennet-Paketes (siehe 'get_on_modules').
disable_on_module() {
	trap 'error_trap disable_on_module "$*"' EXIT
	local module="$1"
	warn_if_unknown_module "$module"
	_is_on_module_enabled "$module" || return 0
	uci_delete_list "on-core.modules.enabled" "$module"
	apply_changes "on-core" "$module"
}


## @fn warn_if_unknown_module()
## @brief Gib eine Warnung aus, falls der angegebene Modul-Name unbekannt ist.
## @param module Name des Opennet-Paketes (siehe 'get_on_modules').
## @details Das Ergebnis der Prüfung ist nur für Warnmeldungen geeignet, da es im Laufe der Zeit
##          Veränderungen in der Liste der bekannten Module geben kann.
warn_if_unknown_module() {
	local module="$1"
	get_on_modules | grep -qwF "$module" && return 0
	echo >&2 "The opennet module name '$module' is unknown - probably misspelled?"
	echo >&2 "The following module names are known: $(get_on_modules | xargs echo)"
}


## @fn warn_if_not_installed_module()
## @brief Gib eine Warnung aus, falls das Opennet-Module nicht installiert ist.
## @param module Name des Opennet-Paketes (siehe 'get_on_modules').
warn_if_not_installed_module() {
	local module="$1"
	is_on_module_installed "$module" && return 0
	echo >&2 "The opennet module name '$module' is not installed - maybe you want to install it?"
}


## @fn get_on_modules()
## @brief Liefere die Namen aller bekannten Opennet-Module zeilenweise getrennt zurück.
## @details Die Liste kann in der Datei ON_CORE_DEFAULTS_FILE angepasst werden.
get_on_modules() {
	# zeilenweise splitten (wir erwarten nur kleine Buchstaben und Zahlen im Namen)
	get_on_core_default "on_modules" | sed 's/[^a-z0-9-]/\n/g' | grep -v "^$" || true
}


## @fn get_not_installed_on_modules()
## @brief Ermittle diejenigen Module, die aktuell nicht installiert sind.
get_not_installed_on_modules() {
	local module
	for module in $(get_on_modules); do
		is_package_installed "$module" || echo "$module"
	done
}


## @fn was_on_module_installed_before()
## @brief Prüfe ob ein Modul "früher" (vor der letzten manuellen Änderung durch den Benutzer) installiert war.
## @details Diese Prüfung ist hilfreich für die Auswahl von nachträglich zu installierenden Paketen.
## @param module Name des Opennet-Paketes (siehe 'get_on_modules').
was_on_module_installed_before() {
	local module="$1"
	uci_is_in_list "on-core.modules.installed" "$module" && return 0
	trap "" EXIT && return 1
}


## @fn get_missing_modules()
## @brief Ermittle diejenigen Module, die vor dem letzten Upgrade installiert waren.
get_missing_modules() {
	local module
	for module in $(get_on_modules); do
		is_on_module_installed_and_enabled "$module" && continue
		is_package_installed "$module" && continue
		was_on_module_installed_before "$module" && echo "$module"
		true
	done
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
	trap 'error_trap install_from_opennet_repository "$*"' EXIT
	local package
	local not_installed_packages
	not_installed_packages=$(get_not_installed_on_modules)
	run_opennet_opkg "update" && run_opennet_opkg "install" "$@"
	for package in "$@"; do
		if get_on_modules | grep -qwF "$package"; then
			# Eventuell schlug die Installation fehl?
			is_package_installed "$package" || continue
			# Falls es ein opennet-Modul ist, dann aktiviere es automatisch nach der Installation.
			# Dies dürfte für den Nutzer am wenigsten überraschend sein.
			# Wichtig: "enable" in einem neuen Skript-Kontext ausführen, damit sichergestellt ist,
			#          dass die "apply_changes"-Aktion mit den eventuell neuen Funktionen
			#          ausgeführt werden kann.
			on-function enable_on_module "$package"
		fi
	done
	# wir wollen auch indirekt installierte Pakete aktivieren (z.B. on-openvpn via on-captive-portal)
	for package in $not_installed_packages; do
		# unveraendert nicht installiert? Ignorieren ...
		is_package_installed "$package" || continue
		on-function enable_on_module "$package"
	done
	# anschließend speichern wir den aktuellen Zustand, falls _alle_ Pakete installiert wurden
	for package in "$@"; do
		# Paket fehlt? aktuelle Liste nicht speichern, sondern einfach abbrechen
		is_package_installed "$package" || return 0
	done
	save_on_modules_list
}


## @fn remove_opennet_modules()
## @param module Name der oder des zu entfernenden Modules
remove_opennet_modules() {
	# "--force-remove" ist für on-monitoring notwendig, da sonst xinetd wegen einer Änderung
	# /etc/xinet.d/munin nicht entfernt wird
	run_opennet_opkg --autoremove --force-remove remove "$@"
	save_on_modules_list
}


## @fn redirect_to_opkg_opennet_logfile()
## @brief Führe die gegebene Aktion aus und lenke ihre Ausgabe in die opennet-opkg-Logdatei um.
## @details Als irrelevant bekannte Meldungen werden herausgefiltert.
redirect_to_opkg_opennet_logfile() {
	local log_file
	log_file=$(get_custom_log_filename "opkg_opennet")
	"$@" 2>&1 \
		| grep -vE 'resolve_conffiles: Existing conffile /etc/config/(openvpn|olsrd2) is different from the conffile in the new package\. The new conffile will be placed at /etc/config/(openvpn|olsrd2)-opkg\.' \
		| grep -v '^Collected errors:$' >>"$log_file"
}


# Ausführung eines opkg-Kommnados mit der opennet-Repository-Konfiguration und minimaler Ausgabe (nur Fehler) auf stdout.
run_opennet_opkg() {
	trap 'error_trap run_opennet_opkg "$*"' EXIT
	# erzeuge Konfiguration, falls sie noch nicht vorhanden ist
	[ -e "$ON_OPKG_CONF_PATH" ] || generate_opennet_opkg_config >"$ON_OPKG_CONF_PATH"
	# Vor der opkg-Ausführung müssen wir das Verzeichnis /etc/opkg verdecken, da opkg fehlerhafterweise
	# auch bei Verwendung von "--conf" die üblichen Orte nach Konfigurationsdateien durchsucht.
	# TODO: opkg-Bug upstream berichten
	mount -t tmpfs -o size=32k tmpfs /etc/opkg
	# opkg ausfuehren und dabei die angegebene Fehlermeldung ignorieren (typisch fuer Paket-Installation nach Upgrade)
	opkg --verbosity=1 --conf "$ON_OPKG_CONF_PATH" "$@" || true
	umount /etc/opkg
}


## @fn save_on_modules_list()
## @brief Speichere die aktuelle Liste der installierten opennet-Module in der uci-Konfiguration.
## @details Nach einer Aktualisierung ermöglicht diese Sicherung die Nachinstallation fehlender Pakete.
save_on_modules_list() {
	local modname
	_prepare_on_modules
	[ -z "$(uci_get "on-core.modules")" ] && uci set "on-core.modules=modules"
	for modname in $(get_on_modules); do
		if is_package_installed "$modname"; then
			echo "$modname"
		fi
	done | uci_replace_list "on-core.modules.installed"
	apply_changes on-core
}


## @fn clear_cache_opennet_opkg()
## @brief Lösche die eventuell vorhandene opennet-opkg-Konfiguration (z.B. nach einem Update).
clear_cache_opennet_opkg() {
	rm -f "$ON_OPKG_CONF_PATH"
}


## @fn get_default_opennet_opkg_repository_base_url()
## @brief Ermittle die automatisch ermittelte URL für die Nachinstallation von Paketen.
## @returns Liefert die Basis-URL zurueck. Anzuhängen sind im Anschluss z.B. /packages/${arch_cpu_type} oder /targets/${arch}/generic/packages
get_default_opennet_opkg_repository_base_url() {
	trap 'error_trap get_default_opennet_opkg_repository_base_url "$*"' EXIT
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
	echo "$ON_OPKG_REPOSITORY_URL_PREFIX/$version_path"
}


## @fn get_configured_opennet_opkg_repository_base_url()
## @brief Ermittle die aktuell konfigurierte Repository-URL.
get_configured_opennet_opkg_repository_base_url() {
	local url
	_prepare_on_modules
	url=$(uci_get "on-core.modules.repository_url")
	if [ -n "$url" ]; then
		echo "$url"
	else
		get_default_opennet_opkg_repository_base_url
	fi
}


## @fn set_configured_opennet_opkg_repository_url()
## @param repo_url Die neue Repository-URL (bis einschliesslich "/packages").
## @brief Ändere die aktuell konfigurierte Repository-URL.
## @details Die URL wird via uci gespeichert. Falls sie identisch mit der Standard-URL ist, wird die Einstellung gelöscht.
set_configured_opennet_opkg_repository_url() {
	local repo_url="$1"
	_prepare_on_modules
	if [ -z "$repo_url" ] || [ "$repo_url" = "$(get_default_opennet_opkg_repository_base_url "opennet")" ]; then
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
	trap 'error_trap generate_opennet_opkg_config "$*"' EXIT
	# schreibe den Inahlt der neuen OPKG-Konfiguration
	echo "dest root /"
	echo "dest ram /tmp"
	echo "lists_dir ext /var/opkg-lists-opennet"
	echo "option overlay_root /overlay"
	echo

	local base_url
	base_url=$(get_configured_opennet_opkg_repository_base_url)

	# Füge non-core package hinzu (z.B. feeds routing,opennet,luci,...)
	# Hole Architektur und CPU Type
	local arch_cpu_type
	arch_cpu_type=$(opkg status base-files | awk '/Architecture/ {print $2}')
	local noncore_pkgs_url="$base_url/packages/$arch_cpu_type"

	local feed
	for feed in base packages routing luci opennet; do
		echo "src/gz on_$feed $noncore_pkgs_url/$feed"
	done

	# Fuege zusaetzlich eine URL mit core packages hinzu (beinhaltet Kernel Module).
	local arch_path
	# shellcheck source=openwrt/package/base-files/files/etc/openwrt_release
	arch_path=$(. /etc/openwrt_release; echo "$DISTRIB_TARGET")
	local core_pkgs_url="$base_url/targets/$arch_path/packages"
	echo "src/gz on_core $core_pkgs_url"
}


## @fn is_package_installed()
## @brief Prüfe, ob ein opkg-Paket installiert ist.
## @param package Name des Pakets
is_package_installed() {
	trap 'error_trap is_package_installed "$*"' EXIT
	local package="$1"
	local status
	# Korrekte Prüfung: via "opkg list-installed" - leider erzeugt sie locking-Fehlermeldung
	# bei parallelen Abläufen (z.B. Status-Seite).
	#opkg list-installed | grep -q -w "^$package" && return 0
	# schneller als via opkg
	status=$(grep -A 10 "^Package: $package$" "${IPKG_INSTROOT:-}/usr/lib/opkg/status" \
		| grep "^Status:" | head -1 | cut -f 2- -d :)
	[ -z "$status" ] && trap "" EXIT && return 1
	echo "$status" | grep -qE "(deinstall|not-installed)" && trap "" EXIT && return 1
	return 0
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
			# shellcheck source=openwrt/package/base-files/files/etc/init.d/boot
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
