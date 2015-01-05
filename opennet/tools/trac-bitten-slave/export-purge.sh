#!/bin/bash

#
# Opennet trac-bitten-slave Scripts 
# Mathias Mahnke, created 2015/01/04
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
NUMBER="20"
USAGE="Usage: $(basename "$0") <number-of-releases>"
case "$PARAM" in
  help|--help)
    echo "$USAGE"
    exit 0
    ;;
  *)
    if [ $# -gt 1 ]; then
      echo "$USAGE"
      echo "Parameter missing."
      exit 1
    fi
    if [ "$PARAM" -gt 1 ]; then
      NUMBER="$PARAM"
    else
      echo "$USAGE"
      echo "Parameter not a valid number (>1)."
      exit 1
    fi
    ;;
esac

# purge export folder based on number of releases
( cd "$HOME/$EXPORT_DIR" && ((ls -t|head -n "$NUMBER";ls)|sort|uniq -u|xargs -d '\n' rm) )

# return
exit 0
