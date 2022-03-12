#!/bin/bash

# stop on error and unset variables
set -eu

BUILD_DIR="."
BIN_DIR="$BUILD_DIR/openwrt/bin"
DOC_DIR="$BUILD_DIR/build-doc/api/html"
OPENWRT_CONFIG="$BUILD_DIR/openwrt/.config"

EXPORT_SERVER="ruri.on"
EXPORT_SSH_USER=trac-bitten-slave
EXPORT_DIR="~/export"  # this folder is on remote download server
RSYNC_OPTIONS="--archive"

snapshot_name=$(grep "^CONFIG_VERSION_NUMBER=" "$OPENWRT_CONFIG" | cut -f 2 -d '"')
[ -z "$snapshot_name" ] && return 1

# set version number in export directories
commit_info=$(git log --oneline | sed -n '1!G;h;$p' | nl | tac)
echo $commit_info > "$BIN_DIR/__${snapshot_name}__"

# allow retrieval of "latest" version by clients
# URL: https://downloads.opennet-initiative.de/openwrt/stable/latest/version.txt
echo "$snapshot_name" >"$BIN_DIR/version.txt"

# generate a map between devices and upgrade firmware download paths
"$BUILD_DIR/opennet/tools/device-upgrade-mapper.sh" generate \
	>"$BIN_DIR/device-upgrade-map.csv"

echo "Copy generated files to download server ..."
rsync -az -e "ssh -i /var/lib/buildbot/.ssh/ssh_host_rsa_key -o PasswordAuthentication=no -o StrictHostKeyChecking=no" $BIN_DIR $EXPORT_SSH_USER@$EXPORT_SERVER:$EXPORT_DIR/$snapshot_name/

