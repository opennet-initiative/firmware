get_client_cn() {
	openssl x509 -in /etc/openvpn/opennet_user/on_aps.crt \
		-subject -nameopt multiline -noout 2>/dev/null | awk '/commonName/ {print $3}'
}

msg_debug() {
	[ -z "$DEBUG" ] && DEBUG=$(uci_get on-core.settings.debug)
	[ -z "$DEBUG" ] && DEBUG=false
	uci_is_true "$DEBUG" && logger -t "$(basename "$0")[$$]" "$1" || true
}

msg_info() {
	logger -t "$(basename "$0")[$$]" "$1"
}

# update a file if its content changed
# return exitcode=0 (success) if the file was updated
# return exitcode=1 (failure) if there was no change
update_file_if_changed() {
	local target_filename="$1"
	local content="$(cat -)"
	if [ -e "$target_filename" ] && echo "$content" | cmp -s - "$target_filename"; then
		# the content did not change
		trap "" $GUARD_TRAPS && return 1
	else
		# updated content
		echo "$content" > "$target_filename"
		return 0
	fi
}


# Gather the list of hosts announcing a NTP services.
# Store this list as a dnsmasq 'server-file'.
# The file is only updated in case of changes.
update_dns_servers() {
	trap "error_trap update_dns_servers '$*'" $GUARD_TRAPS
	local host
	local port
	local service
	local use_dns="$(uci_get on-core.settings.use_olsrd_dns)"
	# return if we should not use DNS servers provided via olsrd
	uci_is_false "$use_dns" && return 0
	local servers_file=$(uci_get "dhcp.@dnsmasq[0].serversfile")
	# aktiviere die "dnsmasq-serversfile"-Direktive, falls noch nicht vorhanden
	if [ -z "$servers_file" ]; then
	       servers_file=$DNSMASQ_SERVERS_FILE_DEFAULT
	       uci set "dhcp.@dnsmasq[0].serversfile=$servers_file"
	       uci commit "dhcp.@dnsmasq[0]"
	       reload_config
	fi
	# wir sortieren alphabetisch - Naehe ist uns egal
	get_sorted_services dns | filter_enabled_services | sort | while read service; do
		host=$(get_service_value "$service" "host")
		port=$(get_service_value "$service" "port")
		[ -n "$port" -a "$port" != "53" ] && host="$host#$port"
		echo "server=$host"
	done | update_file_if_changed "$servers_file" || return 0
	# es gab eine Aenderung
	msg_info "updating DNS servers"
	killall -s HUP dnsmasq	# reload config
}

# Gather the list of hosts announcing a NTP services.
# Store this list as ntpclient-compatible uci settings.
# The uci settings are only updated in case of changes.
# ntpclient is restarted in case of changes.
update_ntp_servers() {
	trap "error_trap update_ntp_servers '$*'" $GUARD_TRAPS
	local host
	local port
	local service
	local use_ntp="$(uci_get on-core.settings.use_olsrd_ntp)"
	# return if we should not use NTP servers provided via olsrd
	uci_is_false "$use_ntp" && return
	# schreibe die Liste der NTP-Server neu
	uci_delete system.ntp.server
	# wir sortieren alphabetisch - Naehe ist uns egal
	get_sorted_services ntp | filter_enabled_services | sort | while read service; do
		host=$(get_service_value "$service" "host")
		port=$(get_service_value "$service" "port")
		[ -n "$port" -a "$port" != "123" ] && host="$host:$port"
		uci_add_list "system.ntp.server" "$host"
	done
	apply_changes system
}


add_banner_event() {
	trap "error_trap add_banner_event '$*'" $GUARD_TRAPS
	local event=$1
	local timestamp=$(date)
	local line_suffix=" - $event -------"
	local line=" - $timestamp "
	local length=$((54-${#line_suffix}))
	(
		# Steht unser Text schon im Banner? Ansonsten hinzufuegen ...
		if grep -q 'clean_restart_log' /etc/banner; then
			true
		else
			echo " ----- clean this log with 'clean_restart_log' -------"
			echo " ------ restart times: (possibly by watchdog) --------"
		fi
		while [ "${#line}" -lt "$length" ]; do line="$line-"; done
		echo "$line$line_suffix"
	) >>/etc/banner
	sync
}


#################################################################################
# Auslesen eines Werts aus einer Key/Value-Datei
# Jede Zeile dieser Datei enthaelt einen Feldnamen und einen Wert - beide sind durch
# ein beliebiges whitespace-Zeichen getrennt.
# Wir verwenden dies beispielsweise fuer die volatilen Gateway-Zustandsdaten.
# Parameter status_file: der Name der Key/Value-Datei
# Parameter field: das Schluesselwort
_get_file_dict_value() {
	local status_file=$1
	local field=$2
	local key
	local value
	# fehlende Datei -> kein Ergebnis
	[ -e "$status_file" ] || return 0
	while read key value; do
		[ "$field" = "$key" ] && echo -n "$value" && return || true
	done < "$status_file"
	return 0
}


# Liefere alle Schluessel aus einer Key/Value-Datei, die mit dem mitgelieferten "keystart"
# beginnen.
_get_file_dict_keys() {
	local status_file=$1
	local keystart=$2
	local key
	local value
	# fehlende Datei -> kein Ergebnis
	[ -e "$status_file" ] || return 0
	while read key value; do
		# leerer oder passender Schluessel-Praefix
		[ -z "$keystart" -o "${key#$keystart}" != "$key" ] && echo "${key#$keystart}" || true
	done < "$status_file"
	return 0
}


#################################################################################
# Schreiben eines Werts in eine Key-Value-Datei
# Dateiformat: siehe _get_file_dict_value
# Parameter status_file: der Name der Key/Value-Datei
# Parameter field: das Schluesselwort
# Parameter value: der neue Wert
_set_file_dict_value() {
	local status_file=$1
	local field=$2
	local new_value=$3
	local fieldname
	local value
	# fehlende Datei? Leer erzeugen ...
	[ -e "$status_file" ] || touch "$status_file"
	# Filtere bisherige Zeilen mit dem key heraus.
	# Fuege anschliessend die Zeile mit dem neuen Wert an.
	# Die Sortierung sorgt fuer gute Vergleichbarkeit, um die Anzahl der
	# Schreibvorgaenge (=Wahrscheinlichkeit von gleichzeitigem Zugriff) zu reduzieren.
	(
		while read fieldname value; do
			[ "$field" != "$fieldname" -a -n "$fieldname" ] && echo "$fieldname $value" || true
		 done <"$status_file"
		# leerer Wert -> loeschen
		[ -n "$new_value" ] && echo "$field $new_value"
	) | sort | update_file_if_changed "$status_file" || true
}


# hole einen der default-Werte der aktuellen Firmware
# Die default-Werte werden nicht von der Konfigurationsverwaltung uci verwaltet.
# Somit sind nach jedem Upgrade imer die neuesten Standard-Werte verfuegbar.
get_on_core_default() { _get_file_dict_value "$ON_CORE_DEFAULTS_FILE" "$1"; }
get_on_openvpn_default() { _get_file_dict_value "$ON_OPENVPN_DEFAULTS_FILE" "$1"; }
get_on_wifidog_default() { _get_file_dict_value "$ON_WIFIDOG_DEFAULTS_FILE" "$1"; }


#################################################################################
# Auslesen einer Gateway-Information
# Parameter ip: IP-Adresse des Gateways
# Parameter key: Informationsschluessel ("age", "status", ...)
get_gateway_value() {
	_get_file_dict_value "$GATEWAY_STATUS_FILE" "${1}_${2}"
}

#################################################################################
# Aendere eine gateway-Information
# Parameter ip: IP-Adresse des Gateways
# Parameter key: Informationsschluessel ("age", "status", ...)
# Parameter value: der neue Inhalt
set_gateway_value() {
	_set_file_dict_value "$GATEWAY_STATUS_FILE" "${1}_${2}" "$3"
}


get_on_firmware_version() {
	opkg status on-core | awk '{if (/Version/) print $2;}'
}


# Parameter:
#   on_id: die ID des AP - z.B. "1.96" oder "2.54"
#   on_ipschema: siehe "get_on_core_default on_ipschema"
#   interface_number: 0..X
# ACHTUNG: manche Aufrufende verlassen sich darauf, dass on_id_1 und
# on_id_2 nach dem Aufruf verfuegbar sind (also _nicht_ "local")
get_on_ip() {
	local on_id=$1
	local on_ipschema=$2
	local no=$3
	echo "$on_id" | grep -q "\." || on_id=1.$on_id
	on_id_1=$(echo "$on_id" | cut -d . -f 1)
	on_id_2=$(echo "$on_id" | cut -d . -f 2)
	echo $(eval echo $on_ipschema)
}


# Liefere die aktuell konfigurierte Main-IP zurueck
get_main_ip() {
	local on_id=$(uci_get on-core.settings.on_id "$(get_on_core_default on_id_preset)")
	local ipschema=$(get_on_core_default on_ipschema)
	get_on_ip "$on_id" "$ipschema" 0
}


# check if a given lock file:
# A) exists, but it is outdated (determined by the number of minutes given as second parameter)
# B) exists, but is fresh
# C) does not exist
# A + C return success and create that file
# B return failure and do not touch that file
aquire_lock() {
	local lock_file=$1
	local max_age_minutes=$2
	[ ! -e "$lock_file" ] && touch "$lock_file" && return 0
	local file_timestamp=$(get_file_modification_timestamp_minutes "$lock_file")
	# too old? We claim it for ourself.
	is_timestamp_older_minutes "$file_timestamp" "$max_age_minutes" && touch "$lock_file" && return 0
	# lockfile is too young
	trap "" $GUARD_TRAPS && return 1
}


clean_stale_pid_file() {
	local pidfile=$1
	local pid
	[ -e "$pidfile" ] || return 0
	pid=$(cat "$pidfile" | sed 's/[^0-9]//g')
	[ -z "$pid" ] && msg_debug "removing broken PID file: $pidfile" && rm "$pidfile" && return 0
	[ ! -e "/proc/$pid" ] && msg_debug "removing stale PID file: $pidfile" && rm "$pidfile" && return 0
	return 0
}


apply_changes() {
	local config=$1
	# keine Aenderungen?
	# "on-core" achtet auch auf nicht-uci-Aenderungen (siehe PERSISTENT_SERVICE_STATUS_DIR)
	[ -z "$(uci changes "$config")" -a "$config" != "on-core" ] && return 0
	uci commit "$config"
	case "$config" in
		system|network|firewall)
			reload_config || true
			;;
		olsrd)
			/etc/init.d/olsrd restart || true
			;;
		openvpn)
			/etc/init.d/openvpn reload || true
			;;
		on-usergw)
			update_openvpn_ugw_settings
			apply_changes openvpn
			apply_changes olsrd
			apply_changes firewall
			;;
		on-core)
			update_ntp_servers
			update_dns_servers
			;;
		*)
			msg_info "no handler defined for applying config changes for '$config'"
			;;
	esac
	return 0
}


# Setzen einer Opennet-ID.
# 1) Hostnamen setzen
# 2) IPs fuer alle Opennet-Interfaces setzen
# 3) Main-IP in der olsr-Konfiguration setzen
# 4) IP des Interface "free" setzen
# 5) DHCP-Redirect fuer wifidog setzen
set_opennet_id() {
	local new_id=$1
	local network
	local uci_prefix
	local ipaddr
	local main_ipaddr
	local free_ipaddr
	local ipschema
	local netmask
	local if_counter=0
	# ID normalisieren (AP7 -> AP1.7)
	echo "$new_id" | grep -q "\." || new_id=1.$new_id
	# ON_ID in on-core-Settings setzen
	prepare_on_uci_settings
	uci set "on-core.settings.on_id=$new_id"
	apply_changes on-core
	# Hostnamen konfigurieren
	find_all_uci_sections system system | while read uci_prefix; do
		uci set "${uci_prefix}.hostname=AP-$(echo "$new_id" | tr . -)"
	done
	apply_changes system
	# IP-Adressen konfigurieren
	ipschema=$(get_on_core_default on_ipschema)
	netmask=$(get_on_core_default on_netmask)
	main_ipaddr=$(get_on_ip "$new_id" "$ipschema" 0)
	for network in $(get_sorted_opennet_interfaces); do
		uci_prefix=network.$network
		[ "$(uci_get "${uci_prefix}.proto")" != "static" ] && continue
		ipaddr=$(get_on_ip "$new_id" "$ipschema" "$if_counter")
		uci set "${uci_prefix}.ipaddr=$ipaddr"
		uci set "${uci_prefix}.netmask=$netmask"
		: $((if_counter++))
	done
	# OLSR-MainIP konfigurieren
	olsr_set_main_ip "$main_ipaddr"
	apply_changes olsrd
	# wifidog-Interface konfigurieren
	ipschema=$(get_on_wifidog_default free_ipschema)
	netmask=$(get_on_wifidog_default free_netmask)
	free_ipaddr=$(get_on_ip "$new_id" "$ipschema" 0)
	uci_prefix=network.$NETWORK_FREE
	uci set "${uci_prefix}=interface"
	uci set "${uci_prefix}.proto=static"
	uci set "${uci_prefix}.ipaddr=$free_ipaddr"
	uci set "${uci_prefix}.netmask=$netmask"
	apply_changes network
	# DHCP-Forwards fuer wifidog
	# Ziel ist beispielsweise folgendes Setup:
	#   firewall.@redirect[0]=redirect
	#   firewall.@redirect[0].src=opennet
	#   firewall.@redirect[0].proto=udp
	#   firewall.@redirect[0].src_dport=67
	#   firewall.@redirect[0].target=DNAT
	#   firewall.@redirect[0].src_port=67
	#   firewall.@redirect[0].dest_ip=10.3.1.210
	#   firewall.@redirect[0].src_dip=192.168.1.210
	find_all_uci_sections firewall redirect "src=$ZONE_MESH" proto=udp src_dport=67 src_port=67 target=DNAT | while read uci_prefix; do
		uci set "${uci_prefix}.name=DHCP-Forward Opennet"
		uci set "${uci_prefix}.dest_ip=$free_ipaddr"
		uci set "${uci_prefix}.src_dip=$main_ipaddr"
	done
	apply_changes firewall
}


# Durchsuche eine Schluessel-Wert-Liste nach einem Schluessel und liefere den dazugehoerigen Wert zurueck.
# Beispiel:
#   foo=bar baz=nux
# Der Separator ist konfigurierbar - standardmaessig wird das Gleichheitszeichen verwendet.
# Die Liste wird auf der Standardeingabe erwartet.
# Der erste und einzige Parameter ist der gewuenschte Schluessel.
get_from_key_value_list() {
	local search_key=$1
	local separator=${2:-=}
	local key_value
	local key
	sed 's/[ \t]\+/\n/g' | while read key_value; do
		key=$(echo "$key_value" | cut -f 1 -d "$separator")
		[ "$key" = "$search_key" ] && echo "$key_value" | cut -f 2- -d "$separator" && break || true
	done
	return 0
}


# Pruefe ob die angegebene Openvpn-Konfiguration auf ein Zertifikat verweist, das nicht existiert.
# Falls der Ort der Zertifikatsdatei nicht zweifelsfrei ermittelt werden kann, dann liefert die
# Funktion "wahr" zurueck.
# Parameter: Name der Openvpn-Konfiguration (uci show openvpn.*)
openvpn_has_certificate() {
	local uci_prefix="openvpn.$1"
	local cert_file
	local config_file=$(uci_get "${uci_prefix}.config")
	if [ -n "$config_file" ]; then
		# Verweis auf lokale config-Datei (keine uci-basierte Konfiguration)
		if [ -e "$config_file" ]; then
			cert_file=$(grep "^cert[ \t]" "$config_file" | while read key value; do echo "$value"; done)
		else
			# im Zweifelsfall: unklar
			cert_file=
		fi
	else
		# Konfiguration liegt in uci
		cert_file=$(uci_get "${uci_prefix}.cert")
	fi
	# das Zertifikat scheint irgendwie anders konfiguriert zu sein - im Zeifelsfall: OK
	[ -z "$cert_file" ] && return 0
	# existiert die Datei?
	[ ! -e "$cert_file" ] && trap "" $GUARD_TRAPS && return 1
	return 0
}


# Wandle einen uebergebenene Parameter in eine Zeichenkette um, die sicher als Dateiname verwendet werden kann
get_safe_filename() {
	echo "$1" | sed 's/[^a-zA-Z0-9._\-]/_/g'
}


# multipliziere eine nicht-ganze Zahl mit einem Faktor und liefere das ganzzahlige Ergebnis zurueck
get_int_multiply() {
	awk '{print int('$1'*$0)}'
}


get_time_minute() {
	date +%s | awk '{print int($1/60)}'
}


get_file_modification_timestamp_minutes() {
	local filename="$1"
	date --reference "$filename" +%s | awk '{ print int($1/60) }'
}

# Achtung: Zeitstempel aus der Zukunft gelten immer als veraltet.
is_timestamp_older_minutes() {
	local timestamp_minute="$1"
	local difference="$2"
	local now="$(get_time_minute)"
	# it is older
	[ "$now" -ge "$((timestamp_minute+difference))" ] && return 0
	# timestamp in future -> invalid -> let's claim it is too old
	[ "$now" -lt "$timestamp_minute" ] && \
		msg_info "WARNING: Timestamp from future found: $timestamp_minute (minutes since epoch)" && \
		return 0
	trap "" $GUARD_TRAPS && return 1
}

