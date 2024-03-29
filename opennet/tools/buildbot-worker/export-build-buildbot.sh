#!/bin/bash

# stop on error and unset variables
set -eu

BUILD_DIR="."
BIN_DIR="$BUILD_DIR/openwrt/bin"
DOC_DIR="$BUILD_DIR/build-doc/api/html"
OPENWRT_CONFIG="$BUILD_DIR/openwrt/.config"

EXPORT_SERVER="downloads.on"
EXPORT_SSH_USER="buildbot"
EXPORT_SSH_KEY="buildbot_rsa_key"
EXPORT_DIR="export"  # this folder is on remote download server
RSYNC_OPTIONS="--archive --verbose"

# cleanup old file
rm -f $BIN_DIR/version.txt
rm -f $BIN_DIR/device-upgrade-map.csv
rm -f $BIN_DIR/__*

snapshot_name=$(grep "^CONFIG_VERSION_NUMBER=" "$OPENWRT_CONFIG" | cut -f 2 -d '"')
[ -z "$snapshot_name" ] && return 1

# set version number in export directories
echo "Generate snapshot version file ..."
commit_info=$(git log --oneline | sed -n '1!G;h;$p' | nl | tac)
echo $commit_info > "$BIN_DIR/__${snapshot_name}__"

# allow retrieval of "latest" version by clients
# URL: https://downloads.opennet-initiative.de/openwrt/stable/latest/version.txt
echo "Generate version TXT file ..."
echo "$snapshot_name" >"$BIN_DIR/version.txt"

# generate a map between devices and upgrade firmware download paths
echo "Generate device upgrade CVS file ..."
"$BUILD_DIR/opennet/tools/device-upgrade-mapper.sh" generate \
	>"$BIN_DIR/device-upgrade-map.csv"

# include documentation into the firmware export
echo "Preparing documentation files for export directory ..."
mkdir -p "$BIN_DIR/doc"
rsync $RSYNC_OPTIONS "$DOC_DIR/" "$BIN_DIR/doc"

# transfer all data to external server
echo "Copy generated files to download server ..."
rsync $RSYNC_OPTIONS -e "ssh -i /var/lib/buildbot/.ssh/$EXPORT_SSH_KEY -o PasswordAuthentication=no" $BIN_DIR/ $EXPORT_SSH_USER@$EXPORT_SERVER:$EXPORT_DIR/$snapshot_name/

