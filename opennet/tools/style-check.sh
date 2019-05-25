#!/bin/sh
#
# Read filenames from stdin and call syntax checking tools for each discovered filetype.
#

set -eu

IGNORED_EXTENSIONS="awk bz2 lua sed pem crt template defaults conf cnf css htm html js png"
IGNORED_PATTERNS="/Makefile \.ipk /keep\.d/ ~$ /\.[^/]\+\.sw[po]$"


is_python() {
	local filename="$1"
	[ "$filename" != "${filename%.py}" ] && return 0
	grep -q "python" "$filename" && return 0
	return 1
}


is_shell() {
	local filename="$1"
	[ "$filename" != "${filename%.sh}" ] && return 0
	# some python/micropython scripts use a shell shebang (see their documentation header)
	grep -q "python" "$filename" && return 1
	grep -q '#!/bin/sh' "$filename" && return 0
	return 1
}


is_ignored() {
	local filename="$1"
	local extension
	for extension in $IGNORED_EXTENSIONS; do
		[ "$filename" != "${filename%.$extension}" ] && return 0
	done
	for pattern in $IGNORED_PATTERNS; do
		echo "$fname" | grep -q "$pattern" && return 0
	done
	return 1
}


ACTION=${1:-}

case "$ACTION" in
	check-python)
		while read -r fname; do
			is_ignored "$fname" && continue
			is_python "$fname" && echo "$fname"
			true
		done | xargs python3 -m flake8 
		;;
	check-shell)
		while read -r fname; do
			is_ignored "$fname" && continue
			is_shell "$fname" && echo "$fname"
			true
		# SC2169: String-Indizierung und --/++ fehlt in dash, wird jedoch von busybox unterstützt
		done | xargs shellcheck --external-sources --exclude SC2169 --shell dash
		;;
	list-unknown)
		while read -r fname; do
			is_python "$fname" && continue
			is_shell "$fname" && continue
			is_ignored "$fname" && continue
			echo "$fname"
		done
		;;
	help|--help)
		echo "Syntax:  $(basename "$0")  { check-python | check-shell | list-unknown | help }"
		echo
		;;
	*)
		"$0" help >&2
		exit 1
		;;
esac
