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
action="${1:-help}"


get_snapshot_name() {
	local input_file="$HOME/$MK_FILE"
	# get revision number
	local version=$(grep "^PKG_VERSION:=" "$input_file" | cut -f 2- -d =)
	local release=$(grep "^PKG_RELEASE:=" "$input_file" | cut -f 2- -d =)
	[ -z "$version" -o -z "$release" ] && echo >&2 "error getting revision numbers from build" && return 1
	echo "$version-$release"
}


get_commit_info() {
	# kurze Uebersicht aller commits des aktuellen Builds inkl. eines Commit-Zaehlers
	git log --oneline | sed -n '1!G;h;$p' | nl | tac
}


build_platform() {
	local platform="$1"
	local snapshot_name=$(get_snapshot_name)
	[ -z "$snapshot_name" ] && return 1

	# prepare export directory
	local dest_dir="$HOME/$EXPORT_DIR/$snapshot_name"
	local dest_platform_dir="$dest_dir/$platform"
	mkdir -p "$dest_platform_dir"

	# copy build to export directory
	local src_dir="$HOME/$BIN_DIR/$platform"
	rsync $RSYNC_OPTIONS "$src_dir/" "$dest_platform_dir/"

	# set version number in export directories
	get_commit_info > "$dest_dir/__${snapshot_name}__"
	get_commit_info > "$dest_platform_dir/__${snapshot_name}__"

	# generate latest link
	rm -f "$HOME/$EXPORT_DIR/$LATEST_LINK"
	(cd "$HOME/$EXPORT_DIR" && ln -s "$snapshot_name" "$LATEST_LINK")
}


export_doc() {
	local snapshot_name=$(get_snapshot_name)
	[ -z "$snapshot_name" ] && return 1
	local dest_dir="$HOME/$EXPORT_DIR/$snapshot_name/doc"
	mkdir -p "$dest_dir"
	local src_dir="$HOME/$DOC_DIR"
	echo "Copying documentation: $src_dir -> $dest_dir"
	rsync $RSYNC_OPTIONS "$src_dir/" "$dest_dir/"
}


purge_old_exports() {
	local keep_builds="$1"
	cd "$HOME/$EXPORT_DIR"
	# "uniq -u" entfernt doppelte Zeilen - also verbleiben nur die alten Dateien
	(
		ls -t | head -n "$keep_builds"
		ls
	) | sort | uniq -u | xargs --delimiter '\n' --no-run-if-empty rm -r
}


# process commands
case "$action" in
	help|--help)
		echo "Usage: $(basename "$0")" 
		echo "	[<platform>]			- export build"
		echo "	--doc				- generate documentation"
		echo "	--purge <keep-number-of-dirs>	- purge old exports"
		exit 0
		;;
	doc|--doc)
		export_doc
		;;
	purge|--purge)
		keep_builds=${2:-}
		[ -z "$keep_builds" ] && echo >&2 "No number of non-purgeable builds given" && exit 2
		echo "$keep_builds" | grep -q "[^0-9]" && echo >&2 "Number of non-purgeable builds contains non-digits: '$keep_builds'" && exit 3
		[ "$keep_builds" -lt 1 ] && echo >&2 "Number of non-purgeable builds is too low: '$keep_builds'" && exit 4
		purge_old_exports "$keep_builds"
		;;
	*)
		build_platform "$action"
		;;
esac

exit 0
