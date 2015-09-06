## @defgroup modules Module
## @brief Verwaltung der Opennet-Module für verschiedene Funktionen/Rollen
# Beginn der Doku-Gruppe
## @{


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
	apply_changes "$module"
}


## @fn disable_on_module()
## @brief Deaktiviere ein Opennet-Modul
## @param module Eins der Opennet-Pakete (siehe 'get_on_modules').
disable_on_module() {
	trap "error_trap disable_on_module '$*'" $GUARD_TRAPS
	local module="$1"
	_is_on_module_enabled "$module" || return 0
	uci_delete_list "on-core.modules.enabled" "$module"
	apply_changes "$module"
}


## @fn get_on_modules()
## @brief Liefere die Namen aller bekannten Opennet-Module zeilenweise getrennt zurück.
## @details Die Liste kann in der Datei ON_CORE_DEFAULTS_FILE angepasst werden.
get_on_modules() {
	# zeilenweise splitten (wir erwarten nur kleine Buchstaben im Namen)
	get_on_core_default "on_modules" | sed 's/[^a-z-]/\n/g' | grep -v "^$"
}

# Ende der Doku-Gruppe
## @}
