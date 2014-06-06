#!/bin/bash

#
# Opennet trac-bitten-slave Scripts 
# Mathias Mahnke, created 2014/05/05
# Opennet Admin Group <admin@opennet-initiative.de>
#

# stop on error and unset variables
set -eu

# get config file name
FILE="$(basename "$0")"
CFG="${FILE%.*}.cfg"

# get current script dir
HOME="$(dirname $(readlink -f "$0"))"

# read variables
. "$HOME/$CFG"

# retrieve commands
PARAM=""
[ $# -gt 0 ] && PARAM="$1"

# process commands
PLATFORM=""
case "$PARAM" in
  help|--help)
    echo "Usage: $(basename "$0") [<platform>]"
    exit 0
    ;;
  *)
    PLATFORM="/$PARAM"
    ;;
esac

# get revision numbers
step=0
while read line; do
  case "$line" in
    "PKG_VERSION:="*) 
      VERSION="${line#*=}" 
      step=$((step +1))
      ;;
    "PKG_RELEASE:="*) 
      RELEASE="${line#*=}"
      step=$((step +1))
      ;;
  esac
done < "$HOME/$MK_FILE"
[ $step -ne 2 ] && echo >&2 "error getting revision numbers from build" && exit 1

# prepare export directory
DEST_DIR="$HOME/$EXPORT_DIR/$VERSION-$RELEASE$PLATFORM"
mkdir -p "$DEST_DIR"

# copy build to export directory
SRC_DIR="$HOME/$BIN_DIR$PLATFORM/"
rsync $RSYNC_OPTIONS "$SRC_DIR"* "$DEST_DIR"
 
# return
exit 0
