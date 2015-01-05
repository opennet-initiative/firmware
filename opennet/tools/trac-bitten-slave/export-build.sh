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
	local dest_dir="$HOME/$EXPORT_DIR/$snapshot_name/doc"
	mkdir -p "$dest_dir"
	local src_dir="$HOME/$DOC_DIR"
	rsync $RSYNC_OPTIONS "$src_dir/" "$dest_dir/"
}


# process commands
case "$action" in
  help|--help)
    echo "Usage: $(basename "$0") [<platform>]"
    exit 0
    ;;
  doc)
    export_doc
    ;;
  *)
    build_platform "$action"
    ;;
esac

exit 0
