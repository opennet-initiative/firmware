#!/bin/sh

set -eu

BASE_DIR="$(cd "$(dirname "$0")/.."; pwd)"
FW_VERSION="${FW_VERSION:-testing}"
ARCH="${ARCH:-x86}"
FW_BASE_DIR="${FW_BASE_DIR:-$BASE_DIR/fw}"
FW_DIR="${FW_DIR:-$FW_BASE_DIR/$FW_VERSION/$ARCH}"
FW_DOWNLOAD_BASE_URL="http://www.absorb.it/software/opennet/on_firmware"
SUDO_BIN=sudo
HOST_MEMORY=24
RUN_DIR="$BASE_DIR/run"
HOST_DIR="$RUN_DIR/host"
NETWORK_DIR="$RUN_DIR/net"
VNC_BIN="${VNC_BIN:-ssvncviewer}"
QEMU_KEYMAP="${QEMU_KEYMAP:-de}"

QEMU_BIN="${QEMU_BIN:-$(which qemu)}"
QEMU_ARGS=
test "0" != "${USE_KVM:-1}" && QEMU_ARGS="$QEMU_ARGS -enable-kvm"


download_firmware() {
	local target="$1"
	test -e "$target" && return 0
	# cut the last three tokens of the full filename (version/arch/filename)
	local url_relative="$(echo "$target" | tr / '\n' | tail -3 | tr '\n' /)"
	# remove trailing slash
	url_relative="${url_relative%/}"
	mkdir -p "$FW_BASE_DIR/$version/$arch"
	local wget_options="-e robots=off --user-agent=gecko -O -"
	if ! wget $wget_options "$FW_DOWNLOAD_BASE_URL/$url_relative" >"$target"; then
		# alternatively try to download the compressed image (e.g. ext4.gz)
		wget $wget_options "$FW_DOWNLOAD_BASE_URL/${url_relative}.gz" | zcat >"$target"
	 fi
	# delay a bit - otherwise we may get banned
}

get_firmware_kernel() {
	local arch="$1"
	local version="$2"
	local base_dir="$FW_BASE_DIR/$version/$arch"
	test "$arch" = "x86" && echo "$base_dir/openwrt-x86-generic-vmlinuz" && return
	test "$arch" = "ar71xx" && echo "$base_dir/openwrt-ar71xx-generic-vmlinux.elf" && return
	echo >&2 "Unknwon architecture: $arch"
}

get_firmware_image() {
	local arch="$1"
	local version="$2"
	local base_dir="$FW_BASE_DIR/$version/$arch"
	test "$arch" = "x86" && echo "$base_dir/openwrt-x86-generic-rootfs-ext4.img" && return
	test "$arch" = "ar71xx" && echo "$base_dir/openwrt-ar71xx-generic-root.squashfs" && return
	echo >&2 "Unknwon architecture: $arch"
}

get_host_dir() { echo "$HOST_DIR/$1"; }
get_host_serial_socket() { echo "$(get_host_dir "$1")/serial.socket"; }
get_host_monitor_socket() { echo "$(get_host_dir "$1")/monitor.socket"; }
get_host_vnc_socket() { echo "$(get_host_dir "$1")/vnc.socket"; }
get_host_sockets() { get_host_serial_socket "$1"; get_host_monitor_socket "$1"; get_host_vnc_socket "$1"; }
get_network_socket() { echo "$NETWORK_DIR/${1}.socket"; }
get_network_pidfile() { echo "$NETWORK_DIR/${1}.pid"; }
get_network_pidfiles() { find "$NETWORK_DIR" -mindepth 1 -maxdepth 1 -type f -name "*.pid" | sort; }
get_host_pidfile() { echo "$(get_host_dir "$1")/pid"; }
get_host_pidfiles() { find "$HOST_DIR" -mindepth 2 -maxdepth 2 -type f -name "pid" | sort; }

get_qemu_bin() {
	local arch="$1"
	local qemu_arch=i386
	test "$arch" = "x86" && qemu_arch=i386
	test "$arch" = "ar71xx" && qemu_arch=arm
	echo "${QEMU_BIN}-system-$qemu_arch"
}

get_network_configs() {
	# no network settings given
	test "$#" -eq 1 && return
	local net_id="$1"
	local name="$2"
	local mac="$3"
	shift 3
	local socket="$(get_network_socket "$name")"
	echo " -device pcnet,vlan=${net_id},mac=${mac},id=eth${net_id} -net vde,vlan=${net_id},sock=$socket"
	test "$#" -gt 0 && get_network_configs "$((net_id+1))" "$@"
}

start_host() {
	local name="$1"
	local arch="$2"
	local rootfs="$3"
	# no binaries? try to download them ...
	test ! -e "$rootfs" && echo >&2 "No root filesystem found ($rootfs) - trying to download ..." && "$0" download
	test ! -e "$rootfs" && echo >&2 "Could not find the root filesystem ($rootfs) - aborting ..." && return 1
	local kernel="$4"
	shift 4
	local qemu_bin="$(get_qemu_bin "$arch")"
	test ! -e "$qemu_bin" && echo >&2 "Could not find '$qemu_bin' - aborting ..." && return 1
	local networks="$(get_network_configs 0 "$@")"
	local pidfile="$(get_host_pidfile "$name")"
	local qemu_args="$QEMU_ARGS"
	if test -e "$pidfile"; then
		pid="$(cat "$pidfile")"
		# the process exists -> quit silently
		test -n "$pid" -a -d "/proc/$pid" && echo >&2 "The host is already running" && return
		# remove stale pid file
		rm "$pidfile"
	 fi
	mkdir -p "$(get_host_dir "$name")"
	# see http://wiki.openwrt.org/doc/howto/qemu
	test "$arch" = "ar71xx" && qemu_args="$qemu_args -M realview-eb-mpcore"
	# we choose alsa - otherwise pulseaudio errors (or warnings?) will occour
	export QEMU_AUDIO_DRV=alsa
	"$qemu_bin" -name "$name" \
		-m "$HOST_MEMORY" \
		-snapshot \
		-display "vnc=unix:$(get_host_vnc_socket "$name")" \
		-k "$QEMU_KEYMAP" \
		$networks \
		-drive "file=$rootfs,snapshot=on" \
		-kernel "$kernel" -append "root=/dev/sda noapic"  \
		-chardev "socket,id=console,path=$(get_host_serial_socket "$name"),server,nowait" \
		-chardev "socket,id=monitor,path=$(get_host_monitor_socket "$name"),server,nowait" \
		-serial chardev:console \
		-monitor chardev:monitor \
		-pidfile "$pidfile" \
		-daemonize \
		$qemu_args
	get_host_sockets "$name" | while read socket; do
		chmod go-rwx "$socket"
	 done
}


create_network_switch() {
	local name="$1"
	local pidfile="$(get_network_pidfile "$name")"
	test -e "$pidfile" && return
	local socket="$(get_network_socket "$name")"
	mkdir -p "$(dirname "$socket")"
	vde_switch --daemon "--sock=$socket" "--pidfile=$pidfile"
}

create_network_capture() {
	local name="$1"
	local phys_if="$2"
	local gain_root=
	local pidfile="$(get_network_pidfile "$name")"
	test -e "$pidfile" && return
	local socket="$(get_network_socket "$name")"
	mkdir -p "$(dirname "$socket")"
	test "$(id -u)" != 0 && gain_root="$SUDO_BIN"
	$gain_root vde_pcapplug --daemon "--pidfile=$pidfile" "--sock=$socket" "$phys_if"
}

create_network_virtual() {
	local name="$1"
	local ip="$2"
	local netmask="$3"
	local pidfile="$(get_network_pidfile "$name")"
	local gain_root=
	test -e "$pidfile" && return
	local socket="$(get_network_socket "$name")"
	mkdir -p "$(dirname "$socket")"
	test "$(id -u)" != 0 && gain_root="$SUDO_BIN"
	vde_switch --daemon "--sock=$socket" "--pidfile=$pidfile"
	$gain_root vde_plug2tap --daemon "--sock=$socket" "$name"
	$gain_root ifconfig "$name" "$ip" netmask "$netmask" up
}

configure_management_interface() {
	local name="$1"
	local interface="$2"
	local ip="$3"
	local netmask="$4"
	# configure IP
	serial_command "$name" "ifconfig '$interface' '$ip' netmask '$netmask' up"
	# allow traffic
	serial_command "$name" "iptables -I INPUT -i '$interface' -j ACCEPT"
	serial_command "$name" "iptables -I OUTPUT -o '$interface' -j ACCEPT"
}

serial_command() {
	local name="$1"
	shift
	local read_stdin=
	test $# -gt 0 && test "$1" = "-" && read_stdin=1 && shift
	local socket="UNIX-CONNECT:$(get_host_serial_socket "$name")"
	# flush the current output buffer and clear the prompt
	(
		echo
		echo "PS1="
		echo
		sleep 0.5
	) | socat -t 0 STDIO "$socket" >/dev/null 2>/dev/null
	(
		if test -n "$read_stdin"; then
			cat -
		 else
			echo "$@"
		 fi
		sleep 0.5
	) | socat -t 0 STDIO "$socket" | sed 1d
}

copy_dir_to_host() {
	local dir="$1"
	local name="$2"
	tar cf - -C "$dir" . | serial_command "$name" - "tar -C / xf -"
}


ACTION=help
test $# -gt 0 && ACTION="$1" && shift

case "$ACTION" in
	download)
		while read arch version; do
			for filename in $(get_firmware_kernel "$arch" "$version") $(get_firmware_image "$arch" "$version"); do
				download_firmware "$filename"
			 done
		 done <<-EOF
			ar71xx	0.4-5
			x86	0.4-5
EOF
		;;
	wait-host-boot)
		# wait until a host is ready for serial commands
		name="$1"
		timeout="$2"
		counter=0
		until serial_command "$name" pwd | grep -q "^/"; do
			sleep 1
			counter=$((counter+1))
			test "$counter" -ge "$timeout" && break
		 done
		# wait a bit - otherwise network interfaces are not available
		uptime="$(serial_command "$name" "cat /proc/uptime" | cut -f 1 -d .)"
		until test "$uptime" -ge "$timeout"; do sleep 1; uptime="$((uptime+1))"; done
		;;
	start-host)
		name="$1"
		version="$2"
		arch="$3"
		shift 3
		rootfs="$(get_firmware_image "$arch" "$version")"
		kernel="$(get_firmware_kernel "$arch" "$version")"
		start_host "$name" "$arch" "$rootfs" "$kernel" "$@"
		;;
	stop-host)
		name="$1"
		pidfile="$(get_host_pidfile "$name")"
		hostdir="$(dirname "$pidfile")"
		test -e "$pidfile" && pkill --pidfile "$pidfile" || true
		rm -f "$pidfile"
		get_host_sockets "$name" | while read socket; do
			rm -f "$socket"
		 done
		test -d "$hostdir" && rmdir --ignore-fail-on-non-empty "$hostdir"
		;;
	start-net)
		name="$1"
		type="$2"
		shift 2
		case "$type" in
			switch)
				create_network_switch "$name"
				;;
			capture)
				create_network_capture "$name" "$1"
				;;
			virtual)
				create_network_virtual "$name" "$1" "$2"
				;;
			*)
				echo "Invalid network type: $type"
				exit 1
				;;
		 esac
		;;
	stop-net)
		name="$1"
		pidfile="$(get_network_pidfile "$name")"
		netdir="$(dirname "$pidfile")"
		test -e "$pidfile" && pkill --pidfile "$pidfile"
		rm -f "$pidfile"
		test -d "$netdir" && rmdir --ignore-fail-on-non-empty "$netdir"
		;;
	vnc)
		name="$1"
		"$VNC_BIN" "$(get_host_vnc_socket "$name")"
		;;
	command)
		serial_command "$@"
		;;
	host-configure-management)
		name="$1"
		interface="$2"
		ip="$3"
		netmask="$4"
		configure_management_interface "$name" "$interface" "$ip" "$netmask"
		;;
	apply-config)
		name="$1"
		config_dir="$2"
		copy_dir_to_host "$config_dir" "$name"
		;;
	status-hosts)
		for pidfile in $(get_host_pidfiles); do
			pid="$(cat "$pidfile")"
			host="$(basename "$(dirname "$pidfile")")" 
			vnc_socket="$(get_host_vnc_socket "$host")"
			pgrep "qemu" | grep -q "^$pid$" && echo "host=$host pid=$pid vnc_socket=$vnc_socket"
		 done
		;;
	status-nets)
		for pidfile in $(get_network_pidfiles); do
			pid="$(cat "$pidfile")"
			network="$(basename "$pidfile")" 
			network="${network%.pid}"
			pgrep "vde_" | grep -q "^$pid$" && echo "net=$network pid=$pid"
		 done
		;;
	status)
		"$0" status-hosts
		"$0" status-nets
		;;
	help|--help)
		echo "Syntax: $(basename "$0")"
		echo "		download"
		echo "		start-host	NAME	VERSION	ARCH	[[NET_NAME MAC] ...]"
		echo "		stop-host	NAME"
		echo "		prepare-host	NAME"
		echo "		start-net	NAME	[switch | capture INTERFACE | virtual IP NETMASK]"
		echo "		stop-net	NAME"
		echo "		wait-host-boot	NAME"
		echo "		command		NAME	COMMAND"
		echo "		apply-config	NAME	CONFIG_DIR"
		echo "		status-hosts"
		echo "		status-nets"
		echo
		;;
	*)
		"$0" >&2 help
		exit 1
		;;
 esac

exit 0

