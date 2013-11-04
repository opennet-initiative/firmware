#!/bin/sh

set -eu

BASE_DIR=$(cd "$(dirname "$0")/.."; pwd)
FW_VERSION=${FW_VERSION:-testing}
ARCH=${ARCH:-x86}
FW_BASE_DIR=${FW_BASE_DIR:-$BASE_DIR/fw}
FW_DIR=${FW_DIR:-$FW_BASE_DIR/$FW_VERSION/$ARCH}
KVM_BIN=$(which kvm)
QEMU_BIN=$(which qemu)
test "$ARCH" != x86 && QEMU_BIN=$(which qemu-system-$ARCH)
FW_DOWNLOAD_BASE_URL="http://www.absorb.it/software/opennet/on_firmware"

 set -x

start_host() {
	return
}

download_firmware() {
	local version=$1
	local arch=$2
	local filename=$3
	local target="$FW_BASE_DIR/$version/$arch/$filename"
	local tmp_target=${target}.part
	test -e "$target" && return 0
	mkdir -p "$FW_BASE_DIR/$version/$arch"
	wget --continue -e robots=off --user-agent=gecko -O "$tmp_target" "$FW_DOWNLOAD_BASE_URL/$version/$arch/$filename"
	mv "$tmp_target" "$target"
}

get_firmware_kernel() {
	local arch=$1
	test "$arch" = "x86" && echo openwrt-x86-generic-vmlinuz && return
	test "$arch" = "ar71xx" && echo openwrt-ar71xx-generic-vmlinux.bin && return
	echo >&2 "Unknwon architecture: $arch"
}

get_firmware_image() {
	local arch=$1
	test "$arch" = "x86" && echo openwrt-x86-generic-rootfs-squashfs.img && return
	test "$arch" = "ar71xx" && echo openwrt-ar71xx-generic-root.squashfs && return
	echo >&2 "Unknwon architecture: $arch"
}


ACTION=help
test $# -gt 0 && ACTION=$1 && shift

case "$ACTION" in
	download)
		for version in 0.4-5; do
			for arch in ar71xx; do
				for filename in $(get_firmware_kernel "$arch") $(get_firmware_image "$arch"); do
					download_firmware "$version" "$arch" "$filename"
				 done
			 done
		 done
		;;
	help|--help)
		echo "Syntax: $(basename "$0") {download|start-host|stop-host}"
		echo
		;;
	*)
		"$0" >&2 help
		exit 1
		;;
 esac

exit 0

