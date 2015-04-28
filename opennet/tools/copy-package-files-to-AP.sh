#!/bin/sh
#
# Kopiere die Entwicklungsdateien aus dem lokalen Baum auf einen Ziel-AP
# Es werden nur Dateien für diejenigen Pakete übertragen, die auf dem Ziel installiert sind.
# Der einzige erforderliche Paramter ist der Ziel-Host.

set -eu

TARGET_HOST="root@$1"
BASE_DIR=$(cd "$(dirname "$0")/.."; pwd)

RSYNC_OPTS="-ax --exclude '.*.swp' --usermap=':root,*:root' --groupmap=':root,*:root'"
SCP_OPTS="-rp"


# wir wollen nur Dateien fuer diejenigen Pakete übertragen, die tatsächlich installiert sind
get_installed_opennet_packages() {
	ssh "$TARGET_HOST" "opkg list-installed" | grep ^on- | awk '{ print $1 }'
}


# Konstruiere die Parameterliste
get_source_and_target_params_null_terminated() {
	# Quellpfade
	get_installed_opennet_packages | while read pkg; do
		# Verwende null-terminated strings fuer xargs
		printf "%s\0" "$BASE_DIR/packages/$pkg/files/."
	done
	# der Zielpfad
	printf "%s\0" "${TARGET_HOST}:/"
}


get_source_and_target_params_null_terminated | xargs -0 -- rsync $RSYNC_OPTS && exit 0 || echo "rsync failed - falling back to slow scp"
get_source_and_target_params_null_terminated | xargs -0 -- scp $SCP_OPTS

