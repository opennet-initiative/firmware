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
SPICE_PORT_BASE=6100
SPICE_PASSWORD=foo

QEMU_BIN="${QEMU_BIN:-$(which qemu)}"
QEMU_ARGS=
test "0" != "${USE_KVM:-1}" && QEMU_ARGS="$QEMU_ARGS -enable-kvm"


download_firmware() {
	local target="$1"
	local tmp_target="${target}.part"
	test -e "$target" && return 0
	# cut the last three tokens of the full filename (version/arch/filename)
	local url_relative="$(echo "$target" | tr / '\n' | tail -3 | tr '\n' /)"
	# remove trailing slash
	url_relative="${url_relative%/}"
	mkdir -p "$FW_BASE_DIR/$version/$arch"
	wget --continue -e robots=off --user-agent=gecko -O "$tmp_target" "$FW_DOWNLOAD_BASE_URL/$url_relative"
	# delay a bit - otherwise we may get banned
	mv "$tmp_target" "$target"
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
	test "$arch" = "x86" && echo "$base_dir/openwrt-x86-generic-rootfs-squashfs.img" && return
	test "$arch" = "ar71xx" && echo "$base_dir/openwrt-ar71xx-generic-root.squashfs" && return
	echo >&2 "Unknwon architecture: $arch"
}

get_host_dir() { echo "$HOST_DIR/$1"; }
get_serial_socket() { echo "$(get_host_dir "$1")/serial"; }
get_monitor_socket() { echo "$(get_host_dir "$1")/monitor"; }
get_overlay_image() { echo "$(get_host_dir "$1")/overlay.img"; }
get_network_socket() { echo "$NETWORK_DIR/${1}.socket"; }
get_network_pidfile() { echo "$NETWORK_DIR/${1}.pid"; }
get_network_pidfiles() { find "$NETWORK_DIR" -mindepth 1 -maxdepth 1 -type f -name "*.pid" | sort; }
get_host_pidfile() { echo "$(get_host_dir "$1")/pid"; }
get_host_pidfiles() { find "$HOST_DIR" -mindepth 2 -maxdepth 2 -type f -name "pid" | sort; }
get_overlay_dir() { echo "$HOST_DIR/overlay.d"; }

make_overlay_image() {
	local overlay_image="$1"
	local bytes="$2"
	local image_root=
	test $# -gt 2 && image_root="$3"
	test -z "$image_root" && image_root="$(mktemp --directory)"
	/usr/sbin/mkfs.jffs2 "--pad=$bytes" "--root=$image_root" >"$overlay_image"
	rmdir "$image_root"
}

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
	local kernel="$4"
	local vm_id="$5"
	shift 5
	local qemu_bin="$(get_qemu_bin "$arch")"
	local networks="$(get_network_configs 0 "$@")"
	local pidfile="$(get_host_pidfile "$name")"
	local qemu_args="$QEMU_ARGS"
	if test -e "$pidfile"; then
		pid="$(cat "$pidfile")"
		# the process exists -> quit silently
		test -n "$pid" -a -d "/proc/$pid" && echo >2 "The host is already running" && return
		# remove stale pid file
		rm "$pidfile"
	 fi
	mkdir -p "$(get_host_dir "$name")"
	local spice_port="$((SPICE_PORT_BASE+vm_id))"
	# see http://wiki.openwrt.org/doc/howto/qemu
	test "$arch" = "ar71xx" && qemu_args="$qemu_args -M realview-eb-mpcore"
	# create overlay directory image
	local overlay_image="$(get_overlay_image "$name")"
	make_overlay_image "$overlay_image" $((4 * 1024 * 1024))
	# we choose alsa - otherwise pulseaudio errors (or warnings?) will occour
	export QEMU_AUDIO_DRV=alsa
	websockify "$spice_port" -- \
		"$qemu_bin" -name "$name" \
			-m "$HOST_MEMORY" -snapshot \
			-display vnc=:$vm_id \
			$networks \
			-drive "file=$rootfs,snapshot=on" \
			-drive "file=$overlay_image" \
			-kernel "$kernel" -append "root=/dev/sda noapic"  \
			-chardev "socket,id=console,path=$(get_serial_socket "$name"),server,nowait" \
			-chardev "socket,id=monitor,path=$(get_monitor_socket "$name"),server,nowait" \
			-serial chardev:console \
			-monitor chardev:monitor \
			-pidfile "$pidfile" \
			-daemonize \
			$qemu_args

			#-serial "unix:$(get_serial_socket "$name"),server,nowait" \
			#-nographic \
			#-vga none \
			#-spice "port=${spice_port},addr=127.0.0.1,password=$SPICE_PASSWORD" \
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
	local pidfile="$(get_network_pidfile "$name")"
	local gain_root=
	test -e "$pidfile" && return
	local socket="$(get_network_socket "$name")"
	mkdir -p "$(dirname "$socket")"
	test "$(id -u)" != 0 && gain_root="$SUDO_BIN"
	$gain_root vde_plug2tap --daemon "--sock=$socket" "--pidfile=$pidfile" "$name"
}

is_remote_process_running() {
	local name="$1"
	local socket="UNIX-CONNECT:$(get_serial_socket "$name")"
	local stdin_file=/tmp/remote_control.stdin
	echo " test -e '$stdin_file' || echo 'not' 'found'" | socat STDIO "$socket" | grep -q "not found" && return 1
	return 0
}

serial_command() {
	local name="$1"
	shift
	local read_stdin=
	test $# -gt 0 && test "$1" = "-" && read_stdin=1 && shift
	local socket="UNIX-CONNECT:$(get_serial_socket "$name")"
	local monitor="UNIX-CONNECT:$(get_monitor_socket "$name")"
	local stdin_file=/tmp/remote_control.stdin
	local stdout_file=/tmp/remote_control.stdout
	local stderr_file=/tmp/remote_control.stderr
	echo "sendkey ctrl-c" | socat STDIO "$(get_monitor_socket "$name")" >/dev/null
	echo " PS1=" | socat STDIO "$socket" >/dev/null
	if test -n "$read_stdin"; then
		cat -
	 else
		echo -n
 	 fi | send_stream_to_host_file "$name" "$stdin_file"
	echo | socat -t 0 STDIO "$socket" >/dev/null
	echo "    $@ <'$stdin_file' >'$stdout_file' 2>'$stderr_file'; rm '$stdin_file'" \
		| socat -t 0 STDIO "$socket" >/dev/null
	return
	while is_remote_process_running "$name"; do
		sleep 0.3
		echo -n "." >&2
	 done
	get_stream_from_host_file "$name" "$stdout_file"
	get_stream_from_host_file "$name" "$stderr_file" >&2
}

copy_dir_to_host() {
	local dir="$1"
	local name="$2"
	tar cf - -C "$dir" . | serial_command "$name" - "tar -C / xf -"
}

send_stream_to_host_file() {
	local name="$1"
	local socket="UNIX-CONNECT:$(get_serial_socket "$name")"
	local target_file="$2"
	local tmpfile="$(mktemp)"
	cat >"$tmpfile"
	local size="$(cat "$tmpfile" | wc -c)"
	# this does not seem to work safely for special characters
	# sadly "uudecode" is not available on the other side
	echo " dd 'of=$target_file' bs=1 count=$size" | socat STDIO "$socket" >/dev/null
	cat "$tmpfile" | socat STDIO "$socket" >/dev/null
	rm -f "$tmpfile"
}

get_stream_from_host_file() {
	local name="$1"
	local socket="UNIX-CONNECT:$(get_serial_socket "$name")"
	local source_file="$2"
	echo " " "cat '$source_file'" | socat STDIO "$socket" | sed 1d
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
	prepare-host)
		name="$1"
		overlay_dir="$(get_overlay_dir "$name")"
		rm -rf "$overlay_dir"
		mkdir -p "$overlay_dir"
		while test $# -gt 0; do
			cp -r "$1/." "$overlay_dir"
		 done
		;;
	start-host)
		vm_id="$1"
		name="$2"
		version="$3"
		arch="$4"
		shift 4
		rootfs="$(get_firmware_image "$arch" "$version")"
		kernel="$(get_firmware_kernel "$arch" "$version")"
		start_host "$name" "$arch" "$rootfs" "$kernel" "$vm_id" "$@"
		;;
	stop-host)
		name="$1"
		pidfile="$(get_host_pidfile "$name")"
		piddir="$(dirname "$pidfile")"
		test -e "$pidfile" && pkill --pidfile "$pidfile" || true
		rm -f "$pidfile" "$(get_serial_socket "$name")"
		test -d "$piddir" && rmdir --ignore-fail-on-non-empty "$piddir"
		;;
	start-net)
		type="$1"
		name="$2"
		shift 2
		case "$type" in
			switch)
				create_network_switch "$name"
				;;
			capture)
				create_network_capture "$name" "$1"
				;;
			virtual)
				create_network_virtual "$name"
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
		piddir="$(dirname "$pidfile")"
		test -e "$pidfile" && pkill --pidfile "$pidfile"
		rm -f "$pidfile"
		test -d "$piddir" && rmdir --ignore-fail-on-non-empty "$piddir"
		;;
	command)
		serial_command "$@"
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
			pgrep "qemu" | grep -q "^$pid$" && echo "Host $host running"
		 done
		;;
	status-nets)
		for pidfile in $(get_network_pidfiles); do
			pid="$(cat "$pidfile")"
			network="$(basename "$pidfile")" 
			network="${network%.pid}"
			pgrep "vde_" | grep -q "^$pid$" && echo "Net $network running"
		 done
		;;
	status)
		"$0" status-hosts
		"$0" status-nets
		;;
	help|--help)
		echo "Syntax: $(basename "$0")"
		echo "		download"
		echo "		start-host	ID	NAME	VERSION	ARCH	[[NET_NAME MAC] ...]"
		echo "		stop-host	ID"
		echo "		prepare-host	NAME"
		echo "		start-net	TYPE	NAME"
		echo "		stop-net	NAME"
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

		type="$1"
		name="$2"
