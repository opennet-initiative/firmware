#!/bin/sh
#
# Skript fuer die Suche nach unbenutzten Shell- oder Lua-Funktionen.
# Die Ausgabe sollte jedcoh mit Vorsicht verwendet werden: "grep -r FUNC_NAME"
# ist ueblicherweise ein guter Einstieg in die Detail-Analyse.
#

set -eu

BASE_DIR=$(cd "$(dirname "$0")/../packages"; pwd)
cd "$BASE_DIR"


get_lua_files() {
	find on-*/files/usr/lib/lua -type f
}


get_shell_files() {
	(
		grep -rl '^#!/bin/sh'
		grep -rl "GUARD_TRAPS"
	) | sort | uniq
}


get_lua_funcs() {
	local fname
	get_lua_files | while read fname; do grep "^[ \t]*function[ \t]*" "$fname" || true; done \
		| sed 's/^[ \t]*function[ \t]*//' \
		| sed 's/^\([a-zA-Z0-9_]\+\).*$/\1/' \
		| grep -v  "[^a-zA-Z0-9_]" \
		| sort | uniq
}


get_shell_funcs() {
	local fname
	get_shell_files | while read fname; do grep "^[a-zA-Z0-9_]\+[ \t]*(" "$fname" || true; done \
		| sed 's/^\([a-zA-Z0-9_]\+\).*$/\1/' \
		| grep -v  "[^a-zA-Z0-9_]" \
		| sort | uniq
}


get_lua_func_calls() {
	local fname="$1"
	local funcname="$2"
	# normaler lua-Funktionsaufruf
	grep "[^a-zA-Z0-9_]$funcname[ \t]*(" "$fname" || true
	# Funktion als luci-Funktion fuer eine Web-Seite: 'call("foo")'
	grep "call(\"$funcname\")" "$fname" || true
}


get_shell_func_calls() {
	local fname="$1"
	local funcname="$2"
	# shell-Funktionsaufruf
	(
		grep -E "^(.*[^a-zA-Z0-9_]|)$funcname([^a-zA-Z0-9_].*|)$" "$fname" || true
	) | grep -vE "(trap|$funcname\()" | grep -v "^[ \t]*#" || true
}


check_lua_function_in_use() {
	local funcname="$1"
	local fname
	local count=$(get_lua_files | while read fname; do get_lua_func_calls "$fname" "$funcname"; done | wc -l)
	# mehr als ein Vorkommen (inkl. der Definition der Funktion)? -> ok
	[ "$count" -gt 1 ] && return 0
	return 1
}


check_shell_function_in_use() {
	local funcname="$1"
	local fname
	# shell-Funktionsaufrufe duerfen in shell- und in lua-Datei auftauchen
	local count=$( (get_shell_files; get_lua_files) | while read fname; do get_shell_func_calls "$fname" "$funcname"; done | wc -l)
	# mindestens ein Vorkommen? -> ok
	[ "$count" -gt 0 ] && return 0
	return 1
}


ACTION=${1:-check}

case "$ACTION" in
	check)
		"$0" lua-check
		"$0" shell-check
		;;
	lua-check)
		echo "**************** eventuell unbenutzte lua-Funktionen *********************"
		get_lua_funcs | while read funcname; do
			check_lua_function_in_use "$funcname" || echo "$funcname"
		done
		;;
	shell-check)
		echo "*************** eventuell unbenutzte shell-Funktionen ********************"
		get_shell_funcs | while read funcname; do
			check_shell_function_in_use "$funcname" || echo "$funcname"
		done
		;;
	lua-funcs)
		get_lua_funcs | sort
		;;
	shell-funcs)
		get_shell_funcs | sort
		;;
	lua-files)
		get_lua_files | sort
		;;
	shell-files)
		get_shell_files | sort
		;;
	help|--help)
		echo "Syntax: $(basename "$0")  { check | lua-check | shell-check | lua-funcs | shell-funcs | lua-files | shell-files | help }"
		echo
		;;
	*)
		"$0" help >&2
		exit 1
		;;
esac

