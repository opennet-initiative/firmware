#!/bin/sh
#
# Kopiere die Entwicklungsdateien aus dem lokalen Baum auf einen Ziel-AP
# Der einzige erforderliche Paramter ist der Ziel-Host.

set -eu

TARGET_HOST="$1"
BASE_DIR=$(cd "$(dirname "$0")/.."; pwd)
SRC_PACKAGES="on-core on-openvpn on-usergw"

RSYNC_OPTS="-ax --exclude '.*.swp'"
SCP_OPTS="-rp"

# Konstruiere die Parameterliste
get_source_and_target_params_null_terminated() {
	# Quellpfade
	for pkg in $SRC_PACKAGES; do
		# Verwende null-terminated strings fuer xargs
		printf "%s\0" "$BASE_DIR/packages/$pkg/files/."
	done
	# der Zielpfad
	printf "%s\0" "root@${TARGET_HOST}:/"
}

get_source_and_target_params_null_terminated | xargs -0 -- rsync $RSYNC_OPTS && exit 0 || echo "rsync failed - falling back to slow scp"
get_source_and_target_params_null_terminated | xargs -0 -- scp $SCP_OPTS

