GATEWAY_STATUS_FILE=/tmp/on-openvpn_gateways.status
ON_CORE_DEFAULTS_FILE=/usr/share/opennet/core.defaults
ON_OPENVPN_DEFAULTS_FILE=/usr/share/opennet/openvpn.defaults
ON_WIFIDOG_DEFAULTS_FILE=/usr/share/opennet/wifidog.defaults
DNSMASQ_SERVERS_FILE_DEFAULT=/var/run/dnsmasq.servers
REPORTS_FILE=/tmp/on_report.tar.gz


## @fn get_client_cn()
## @brief Ermittle den Common-Name des Nutzer-Zertifikats
## @todo Verschiebung zu on-openvpn - Pruefung auf Existenz der Datei
get_client_cn() {
	openssl x509 -in /etc/openvpn/opennet_user/on_aps.crt \
		-subject -nameopt multiline -noout 2>/dev/null | awk '/commonName/ {print $3}'
}

## @fn msg_debug()
## @param message Debug-Nachricht
## @brief Debug-Meldungen ins syslog schreiben
## @details Die Debug-Nachrichten landen im syslog (siehe ``logread``).
## Falls das aktuelle Log-Level bei ``info`` oder niedriger liegt, wird keine Nachricht ausgegeben.
msg_debug() {
	[ -z "$DEBUG" ] && DEBUG=$(uci_get on-core.settings.debug)
	[ -z "$DEBUG" ] && DEBUG=false
	uci_is_true "$DEBUG" && logger -t "$(basename "$0")[$$]" "$1" || true
}

msg_info() {
	logger -t "$(basename "$0")[$$]" "$1"
}

## @fn update_file_if_changed()
## @param filename Name der Zieldatei
## @brief Aktualisiere eine Datei, falls sich ihr Inhalt geändert haben sollte.
## @details Der neue Inhalt der Datei wird auf der Standardeingabe erwartet.
##   Im Falle der Gleichheit von aktuellem Inhalt und zukünftigem Inhalt wird
##   keine Schreiboperation ausgeführt. Der Exitcode gibt an, ob eine Schreiboperation
##   durchgeführt wurde.
## @return exitcode=0 (Erfolg) falls die Datei geändert werden musste
## @return exitcode=1 (Fehler) falls es keine Änderung gab
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
	# Konfiguration neu einlesen
	killall -s HUP dnsmasq 2>/dev/null || true
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


# Pruefe ob eine PID-Datei existiert und ob die enthaltene PID zu einem Prozess
# mit dem angegebenen Namen (nur Dateiname - ohne Pfad) verweist.
# Parameter PID-Datei: vollstaendiger Pfad
# Parameter Prozess-Name: Dateiname ohne Pfad
check_pid_file() {
	local pid_file="$1"
	local process_name="$2"
	local pid
	local current_process
	[ -z "$pid_file" -o ! -e "$pid_file" ] && trap "" $GUARD_TRAPS && return 1
	pid=$(cat "$pid_file" | sed 's/[^0-9]//g')
	# leere/kaputte PID-Datei
	[ -z "$pid" ] && trap "" $GUARD_TRAPS && return 1
	# Prozess-Datei ist kein symbolischer Link?
	[ ! -L "/proc/$pid/exe" ] && trap "" $GUARD_TRAPS && return 1
	current_process=$(readlink "/proc/$pid/exe")
	[ "$process_name" != "$(basename "$current_process")" ] && trap "" $GUARD_TRAPS && return 1
	return 0
}


apply_changes() {
	local config=$1
	# keine Aenderungen?
	# "on-core" achtet auch auf nicht-uci-Aenderungen (siehe PERSISTENT_SERVICE_STATUS_DIR)
	[ -z "$(uci changes "$config")" -a "$config" != "on-core" ] && return 0
	uci commit "$config"
	case "$config" in
		system|network|firewall|dhcp)
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
			/etc/init.d/openvpn reload || true
			/etc/init.d/olsrd restart || true
			reload_config || true
			;;
		on-core)
			update_ntp_servers
			update_dns_servers
			;;
		on-openvpn)
			# es ist nichts zu tun
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


# Fuehre eine Aktion verzoegert im Hintergrund aus.
# Parameter: Verzoegerung in Sekunden
# Parameter: Kommandozeile
run_delayed_in_background() {
	local delay="$1"
	shift
	(sleep "$delay" && "$@") </dev/null >/dev/null 2>&1 &
}


get_filesize() {
	local filename="$1"
	stat -c %s "$filename"
}


# Bericht erzeugen
# Der Name der erzeugten tar-Datei wird als Ergebnis ausgegeben.
generate_report() {
	trap "error_trap generate_report '$*'" $GUARD_TRAPS
	local fname
	local pid
	local temp_dir=$(mktemp -d)
	local reports_dir="$temp_dir/report"
	local tar_file=$(mktemp)
	msg_debug "Creating a report"
	# die Skripte duerfen davon ausgehen, dass wir uns im Zielverzeichnis befinden
	mkdir -p "$reports_dir"
	cd "$reports_dir"
	find /usr/lib/opennet/reports -type f | while read fname; do
		[ ! -x "$fname" ] && msg_info "skipping non-executable report script: $fname" && continue
		"$fname" || msg_info "ERROR: reports script failed: $fname"
	done
	cd "$temp_dir"
	tar czf "$tar_file" "report"
	rm -r "$temp_dir"
	mv "$tar_file" "$REPORTS_FILE"
}


# Filtere aus den zugaenglichen Quellen moegliche Fehlermeldungen.
# Falls diese Funktion ein nicht-leeres Ergebnis zurueckliefert, dann kann dies als Hinweis fuer den
# Nutzer verwendet werden, auf dass er einen Fehlerbericht einreicht.
get_potential_error_messages() {
	local filters=
	# 1) get_service_as_csv
	#    Wir ignorieren "get_service_as_csv"-Meldungen - diese werden durch asynchrone Anfragen des
	#    Web-Interface ausgeloest, die beim vorzeitigen Abbruch des Seiten-Lade-Vorgangs mit
	#    einem Fehler enden.
	filters="${filters}|trapped.*get_service_as_csv"
	# 2) openvpn.*Error opening configuration file
	#    Beim Booten des Systems wurde die openvpn-Config-Datei, die via uci referenziert ist, noch
	#    nicht erzeugt. Beim naechsten cron-Lauf wird dieses Problem behoben.
	filters="${filters}|openvpn.*Error opening configuration file"
	# 3) openvpn(...)[...]: Exiting due to fatal error
	#    Das Verzeichnis /var/etc/openvpn/ existiert beim Booten noch nicht.
	filters="${filters}|openvpn.*Exiting due to fatal error"
	# 4) openvpn(...)[...]: SIGUSR1[soft,tls-error] received, process restarting
	#    Diese Meldung taucht bei einem Verbindungsabbruch auf. Dieses Ereignis ist nicht
	#    ungewoehnlich und wird mittels des Verbindungsprotokolls bereits hinreichend gewuerdigt
	filters="${filters}|openvpn.*soft,tls-error"
	# 5) openvpn(...)[...]: TLS Error: TLS handshake failed
	#    Diese Meldung deutet einen fehlgeschlagenen Verbindungsversuch an. Dies ist nicht
	#    ungewoehnlich (beispielsweise auch fuer Verbindungstests).
	filters="${filters}|openvpn.*TLS Error"
	# 6) olsrd: /etc/rc.d/S65olsrd: startup-error: check via: '/usr/sbin/olsrd -f "/var/etc/olsrd.conf" -nofork'
	#    Falls noch kein Interface vorhanden ist (z.B. als wifi-Client), dann taucht diese Meldung
	#    beim Booten auf.
	filters="${filters}|olsrd.*startup-error"
	# 7) ucarp
	#    Beim Booten tauchen Fehlermeldungen aufgrund nicht konfigurierter Netzwerk-Interfaces auf.
	#    TODO: ucarp nur noch als nachinstallierbares Paket markieren (erfordert Aenderung der Makefile-Erzeugung)
	filters="${filters}|ucarp"
	# 8) olsrd: /etc/rc.d/S65olsrd: ERROR: there is already an IPv4 instance of olsrd running (pid: '1099'), not starting.
	#    Dieser Fehler tritt auf, wenn der olsrd_check einen olsrd-Neustart ausloest, obwohl er schon laeuft.
	filters="${filters}|olsrd: ERROR: there is already an IPv4 instance of olsrd running"
	# 9) openvpn(...)[...]: Authenticate/Decrypt packet error
	#    Paketverschiebungen nach dem Verbindungsaufbau - anscheinend unproblematisch.
	filters="${filters}|openvpn.*Authenticate/Decrypt packet error"
	# System-Fehlermeldungen (inkl. "trapped")
	logread | grep -i error | grep -vE "(${filters#|})" || true
}


# Im openwrt-Build-Prozess wird aus bisher ungeklaerter Ursache die falsche opkg-Repository-URL gesetzt.
# Diese Funktion erlaubt die einfache Aenderung der opkg-URL.
# Parameter: URL-Bestandteile (z.B. "stable/0.5.0")
set_opkg_download_version() {
	local version="$1"
	sed -i "s#\(/openwrt\)/[^/]\+/[^/]\+/#\1/$version/#" /etc/opkg.conf
}


# Ersetze eine Zeile durch einen neuen Inhalt. Falls das Zeilenmuster nicht vorhanden ist, wird eine neue Zeile eingefuegt.
# Dies entspricht der Funktionalitaet des "lineinfile"-Moduls von ansible.
# Parameter filename: der Dateiname
# Parameter pattern: Suchmuster der zu ersetzenden Zeile
# Parameter new_line: neue Zeile
line_in_file() {
	trap "error_trap lineinfile '$*'" $GUARD_TRAPS
	local filename="$1"
	local pattern="$2"
	local new_line="$3"
	local line
	# Datei existiert nicht? Einfach mit dieser Zeile erzeugen.
	[ ! -e "$filename" ] && echo "$content" >"$filename" && return 0
	# Datei einlesen - zum Muster passende Zeilen austauschen - notfalls neue Zeile anfuegen
	(
		while read line; do
			echo "$line" | grep -q "$pattern" && echo "$new_line" || echo "$line"
		done <"$filename"
		# die neue Zeile hinzufuegen, falls das Muster in der alten Datei nicht vorhanden war
		grep -q "$pattern" "$filename" || echo "$new_line"
	) | update_file_if_changed "$filename" || true
}


# Eine hilfreiche Funktion zur Analyse des Platzbedarfs der installierten Pakete
# Im AP-Betrieb ist sie nicht relevant.
list_installed_packages_by_size() {
	local fname
	find /usr/lib/opkg/info/ -type f -name "*.control" | while read fname; do
		grep "Installed-Size:" "$fname" \
			| awk '{print $2, "\t", "'$(basename "${fname%.control}")'" }'
	done | sort -n | awk 'BEGIN { summe=0 } { summe+=$1; print $0 } END { print summe }'
}


# Pruefe, ob eine Liste ein bestimmtes Element enthaelt
# Die Listenelemente sind durch beliebigen Whitespace getrennt.
is_in_list() {
	local target="$1"
	local list="$2"
	local token
	for token in $list; do
		[ "$token" = "$target" ] && return 0 || true
	done
	# kein passendes Token gefunden
	trap "" $GUARD_TRAPS && return 1
}


# Liefere den Inhalt einer Variable zurueck.
# Dies ist beispielsweise fuer lua-Skripte nuetzlich, da diese nicht den shell-Namensraum teilen.
# Paramter: Name der Variable
get_variable() {
	local var_name="$1"
	eval "echo \"\$$var_name\""
}


# Pruefe, ob die angegebene Funktion definiert ist.
# Dies ersetzt opkg-basierte Pruefungen auf installierte opennet-Firmware-Pakete.
is_function_available() {
	local func_name
	# "ash" liefert leider nicht den korrekten Wert "function" nach einem Aufruf von "type -t".
	# Also verwenden wir die Textausgabe von "type".
	echo "$(type "$1")" | grep -q "function$" && return 0
	trap "" $GUARD_TRAPS && return 1
}
