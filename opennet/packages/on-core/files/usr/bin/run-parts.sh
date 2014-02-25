#!/bin/sh
# rts.sh by macsat@macsat.com
# intended for use with cron
#
# based on rc.unslung by unslung guys :-)
#

[ $# -lt 1 -o -z "$1" -o ! -d "$1" ] && echo "Usage : $0 DIRECTORY" && exit 1


find "$1" -maxdepth 1 -mindepth 1 | while read fname; do

	# Ignore dangling symlinks (if any).
	[ ! -f "$fname" ] && continue

	if [ "$fname" != "${fname%.sh}" ]; then
		# Source shell script for speed.
		( trap - INT QUIT TSTP; set start; . "$fname" )
	else
		# No sh extension, so fork subprocess.
		"$fname" start
	fi
done

