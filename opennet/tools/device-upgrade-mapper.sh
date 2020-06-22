#!/bin/sh
#
# Generate a mapping between devices and upgrade firmware download paths.
#
# The firmware requests the content of such a file from the base download 
# server in order to discover potential upgrade image URLs.
#
# Run this script with the "verify" argument in order to test the URLs:
#    # local build version
#    device-upgrade-mapper.sh verify
#    # latest stable release
#    device-upgrade-mapper.sh verify stable
#    # latest testing release
#    device-upgrade-mapper.sh verify testing
#    # a specific testing release
#    device-upgrade-mapper.sh verify 0.5.6-unstable-2754-695e5ff8
#

set -eu


DEVICE_MAP="
    # Ubiquiti
    loco-m-xw                   ar71xx/generic  ubnt-loco-m-xw-squashfs-sysupgrade.bin
    nanostation-m-xw            ar71xx/generic  ubnt-nano-m-xw-squashfs-sysupgrade.bin
    rocket-m-xw                 ar71xx/generic  ubnt-rocket-m-xw-squashfs-sysupgrade.bin
    ubnt,nanostation-ac         ath79/generic   ubnt_nanostation-ac-squashfs-sysupgrade.bin
    ubnt,nanostation-ac-loco    ath79/generic   ubnt_nanostation-ac-loco-squashfs-sysupgrade.bin
    ubnt,litebeam-ac-gen1       ath79/generic   ubnt_litebeam-ac-gen1-squashfs-sysupgrade.bin
    ubnt,litebeam-ac-gen2       ath79/generic   ubnt_litebeam-ac-gen2-squashfs-sysupgrade.bin
    ubnt,nanobeam-ac            ath79/generic   ubnt_nanobeam-ac-squashfs-sysupgrade.bin
    ubnt-erx                    ramips/mt7621   ubnt-erx-squashfs-sysupgrade.bin
    ubnt-erx-sfp                ramips/mt7621   ubnt-erx-sfp-squashfs-sysupgrade.bin

    # TP-Link
    tl-wr1043nd                 ar71xx/generic  tl-wr1043nd-v1-squashfs-sysupgrade.bin
    tl-wr1043nd-v2              ar71xx/generic  tl-wr1043nd-v2-squashfs-sysupgrade.bin
    tl-wr1043nd-v3              ar71xx/generic  tl-wr1043nd-v3-squashfs-sysupgrade.bin
    tplink,tl-wr1043nd-v4       ath79/generic   tplink_tl-wr1043nd-v4-squashfs-sysupgrade.bin
    tplink,tl-wr1043n-v5        ath79/generic   tplink_tl-wr1043n-v5-squashfs-sysupgrade.bin
    tl-wdr3500                  ar71xx/generic  tl-wdr3500-v1-squashfs-sysupgrade.bin
    tl-wdr4300                  ar71xx/generic  tl-wdr4300-v1-squashfs-sysupgrade.bin
    cpe210                      ar71xx/generic  cpe210-220-v1-squashfs-sysupgrade.bin
    tplink,cpe210-v2            ath79/generic   tplink_cpe210-v2-squashfs-sysupgrade.bin
    tplink,cpe210-v3            ath79/generic   tplink_cpe210-v3-squashfs-sysupgrade.bin
    cpe510                      ar71xx/generic  cpe510-520-v1-squashfs-sysupgrade.bin
    cpe510-v2                   ar71xx/generic  cpe510-v2-squashfs-sysupgrade.bin
    tplink,cpe510-v3            ath79/generic   tplink_cpe510-v3-squashfs-sysupgrade.bin
    tplink,archer-c7-v1         ath79/generic   tplink_archer-c7-v1-squashfs-factory.bin
    tplink,archer-c7-v2         ath79/generic   tplink_archer-c7-v2-squashfs-factory.bin
    tplink,archer-c7-v4         ath79/generic   tplink_archer-c7-v4-squashfs-factory.bin
    tplink,archer-c7-v5         ath79/generic   tplink_archer-c7-v5-squashfs-factory.bin

    # MikroTik
    rb-921gs-5hpacd-r2          ar71xx/mikrotik nand-large-ac-squashfs-sysupgrade.bin

    # X86
    bochs-bochs                 x86/generic     combined-squashfs.img.gz
    pc-engines-apu              x86/generic     combined-squashfs.img.gz

    # Raspberry
    raspberrypi,model-b         brcm2708/bcm2708 rpi-squashfs-sysupgrade.img.gz
    raspberrypi,model-b-plus    brcm2708/bcm2708 rpi-squashfs-sysupgrade.img.gz
    raspberrypi,model-b-rev2    brcm2708/bcm2708 rpi-squashfs-sysupgrade.img.gz
    raspberrypi,model-zero-w    brcm2708/bcm2708 rpi-squashfs-sysupgrade.img.gz
    raspberrypi,2-model-b       brcm2708/bcm2709 rpi-2-squashfs-sysupgrade.img.gz
    raspberrypi,2-model-b-rev2  brcm2708/bcm2709 rpi-2-squashfs-sysupgrade.img.gz
    raspberrypi,3-model-b       brcm2708/bcm2710 rpi-3-squashfs-sysupgrade.img.gz
    raspberrypi,3-model-b-plus  brcm2708/bcm2710 rpi-3-squashfs-sysupgrade.img.gz
    #raspberrypi,4-model-b      #not supported yet

    # AVM
    avm,fritzbox-4040           ipq40xx/generic  avm_fritzbox-4040-squashfs-sysupgrade.bin

    # Comfast
    comfast,cf-ew72             ath79/generic    comfast_cf-ew72-squashfs-sysupgrade.bin

"

BASE_DIR=$(cd "$(dirname "$0")/../.."; pwd)
OPENWRT_CONFIG="$BASE_DIR/openwrt/.config"
BASE_DOWNLOAD_URL="https://downloads.opennet-initiative.de/openwrt"


get_local_build_release() {
	local dist number
	grep "^CONFIG_VERSION_NUMBER=" "$OPENWRT_CONFIG" | cut -f 2 -d '"'
}


if [ $# -gt 0 ]; then
	ACTION=$1
	shift
else
	ACTION="help"
fi


case "$ACTION" in
	generate)
		if [ $# -lt 1 ]; then
			RELEASE=$(get_local_build_release)
		elif [ "$1" = "stable" ]; then
			RELEASE=$(curl -sS --fail "$BASE_DOWNLOAD_URL/stable/latest/version.txt")
		elif [ "$1" = "testing" ]; then
			RELEASE=$(curl -sS --fail "$BASE_DOWNLOAD_URL/testing/latest/version.txt")
		else
			RELEASE=$1
		fi
		echo "$DEVICE_MAP" | grep '^\s*[a-z]' | while read -r device arch suffix; do
			printf '%s	targets/%s/openwrt-%s-%s-%s\n' \
				"$device" "$arch" "$RELEASE" "$(echo "$arch" | tr "/" "-")" "$suffix"
			done | sort -n
		;;
	verify)
		if [ $# -lt 1 ]; then
			PATH_PREFIX="testing/$(get_local_build_release)"
		elif [ "$1" = "stable" ]; then
			PATH_PREFIX="stable/latest"
		elif [ "$1" = "testing" ]; then
			PATH_PREFIX="testing/latest"
		else
			PATH_PREFIX="testing/$1"
		fi
		"$0" generate "$@" | while read -r device path; do
			url="${BASE_DOWNLOAD_URL%/}/$PATH_PREFIX/$path"
			if ! curl -I -s --fail "$url" >/dev/null; then
				echo >&2 "Failed: $url"
				exit 1
			fi
		done
		;;
	help|--help)
		echo "Syntax:  $(basename "$0")  { generate | verify }  [VERSION]"
		echo
		echo "VERSION is automatically determined (from build local environment), if missing"
		echo
		;;
	*)
		"$0" help >&2
		exit 1
		;;
esac
