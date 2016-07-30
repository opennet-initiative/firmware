#!/bin/sh
#
# Kopiere die Entwicklungsdateien aus dem lokalen Baum auf einen Ziel-AP
# Es werden nur Dateien für diejenigen Pakete übertragen, die auf dem Ziel installiert sind.
# Der einzige erforderliche Paramter ist der Ziel-Host.

set -eu

TARGET_HOST="root@$1"
BASE_DIR=$(cd "$(dirname "$0")/.."; pwd)

RSYNC_OPTS="-ax --exclude=.*.swp --usermap=:root,*:root --groupmap=:root,*:root"
SCP_OPTS="-rp"
shift
PACKAGES="$@"

# falls nichts explizit gewünscht wurde, wollen wi nur Dateien fuer diejenigen Pakete übertragen, die tatsächlich installiert sind
[ -z "$PACKAGES" ] && PACKAGES=$(ssh "$TARGET_HOST" "opkg list-installed" | grep ^on- | awk '{ print $1 }')


# Konstruiere die Parameterliste
get_source_and_target_params_null_terminated() {
	local path
	# Quellpfade
	for pkg in $PACKAGES; do
		# Verwende null-terminated strings fuer xargs
		path="$BASE_DIR/packages/$pkg/files/."
		[ -e "$path" ] && printf "$path\0"
		true
	done
	# der Zielpfad
	printf "%s\0" "${TARGET_HOST}:/"
}


get_source_and_target_params_null_terminated | xargs -0 -- rsync $RSYNC_OPTS || {
	echo "rsync failed - falling back to slow scp"
	get_source_and_target_params_null_terminated | xargs -0 -- scp $SCP_OPTS
}
# vorsichtshalber: luci-Neustart und shell-Modul-Cleanup
ssh "$TARGET_HOST" "on-function clear_caches"
