## @defgroup core Kern
## @brief Logging, Datei-Operationen, DNS- und NTP-Dienste, Dictionary-Dateien, PID- und Lock-Behandlung, Berichte
# Beginn der Doku-Gruppe
## @{


## @var Quelldatei für Standardwerte des Kern-Pakets
ON_CORE_DEFAULTS_FILE=/usr/share/opennet/core.defaults
## @var Quelldatei für Standardwerte des Nutzer-VPN-Pakets
ON_OPENVPN_DEFAULTS_FILE=/usr/share/opennet/openvpn.defaults
## @var Quelldatei für Standardwerte des Hotspot-Pakets
ON_WIFIDOG_DEFAULTS_FILE=/usr/share/opennet/wifidog.defaults
## @var Pfad zur dnsmasq-Server-Datei zur dynamischen Aktualisierung durch Dienste-Erkennung
DNSMASQ_SERVERS_FILE_DEFAULT=/var/run/dnsmasq.servers
## @var Dateiname für erstellte Zusammenfassungen
REPORTS_FILE=/tmp/on_report.tar.gz
## @var Basis-Verzeichnis für Log-Dateien
LOG_BASE_DIR=/var/log
# beim ersten Pruefen wird der Debug-Modus ermittelt
DEBUG_ENABLED=



## @fn msg_debug()
## @param message Debug-Nachricht
## @brief Debug-Meldungen ins syslog schreiben
## @details Die Debug-Nachrichten landen im syslog (siehe ``logread``).
## Falls das aktuelle Log-Level bei ``info`` oder niedriger liegt, wird keine Nachricht ausgegeben.
msg_debug() {
	# bei der ersten Ausfuehrung dauerhaft speichern
	[ -z "$DEBUG_ENABLED" ] && \
		DEBUG_ENABLED=$(uci_is_true "$(uci_get on-core.settings.debug false)" && echo 1 || echo 0)
	[ "$DEBUG_ENABLED" = "0" ] || logger -t "$(basename "$0")[$$]" "$1"
}


## @fn msg_info()
## @param message Log-Nachricht
## @brief Informationen und Fehlermeldungen ins syslog schreiben
## @details Die Nachrichten landen im syslog (siehe ``logread``).
## Die info-Nachrichten werden immer ausgegeben, da es kein höheres Log-Level gibt.
msg_info() {
	logger -t "$(basename "$0")[$$]" "$1"
}


## @fn append_to_custom_log()
## @brief Hänge eine neue Nachricht an ein spezfisches Protokoll an.
## @param log_name Name des Log-Ziels
## @param event die Kategorie der Meldung (up/down/???)
## @param msg die textuelle Beschreibung des Ereignis (z.B. "connection with ... closed")
## @details Die Meldungen werden beispielsweise von den konfigurierten openvpn-up/down-Skripten gesendet.
append_to_custom_log() {
	local log_name="$1"
	local event="$2"
	local msg="$3"
	local logfile="$LOG_BASE_DIR/${log_name}.log"
	echo "$(date) openvpn [$event]: $msg" >>"$logfile"
	# Datei kuerzen, falls sie zu gross sein sollte
	local filesize=$(get_filesize "$logfile")
	[ "$filesize" -gt 10000 ] && sed -i "1,30d" "$logfile"
	return 0
}


## @fn get_custom_log()
## @brief Liefere den Inhalt eines spezifischen Logs (z.B. das OpenVPN-Verbindungsprotokoll) zurück.
## @param log_name Name des Log-Ziels
## @returns Zeilenweise Ausgabe der Protokollereignisse (aufsteigend nach Zeitstempel sortiert).
get_custom_log() {
	local log_name="$1"
	local logfile="$LOG_BASE_DIR/${log_name}.log"
	[ -e "$logfile" ] && cat "$logfile" || true
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
		local dirname=$(dirname "$target_filename")
		[ -d "$dirname" ] || mkdir -p "$dirname"
		echo "$content" > "$target_filename"
		return 0
	fi
}


## @fn update_dns_servers()
## @brief Übertrage die Liste der als DNS-Dienst announcierten Server in die dnsmasq-Konfiguration.
## @details Die Liste der DNS-Server wird in die separate dnsmasq-Servers-Datei geschrieben (siehe @sa DNSMASQ_SERVERS_FILE_DEFAULT).
##   Die Server-Datei wird nur bei Änderungen neu geschrieben. Dasselbe gilt für den Neustart des Diensts.
##   Diese Funktion sollte via olsrd-nameservice-Trigger oder via cron-Job ausgeführt werden.
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
	get_services "dns" | filter_reachable_services | filter_enabled_services | sort | while read service; do
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


## @fn update_ntp_servers()
## @brief Übertrage die Liste der als NTP-Dienst announcierten Server in die sysntpd-Konfiguration.
## @details Die Liste der NTP-Server wird in die uci-Konfiguration geschrieben.
##   Die uci-Konfiguration wird nur bei Änderungen neu geschrieben. Dasselbe gilt für den Neustart des Diensts.
##   Diese Funktion sollte via olsrd-nameservice-Trigger oder via cron-Job ausgeführt werden.
## @sa http://wiki.openwrt.org/doc/uci/system#remote_time_ntp
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
	get_services "ntp" | filter_reachable_services | filter_enabled_services | sort | while read service; do
		host=$(get_service_value "$service" "host")
		port=$(get_service_value "$service" "port")
		[ -n "$port" -a "$port" != "123" ] && host="$host:$port"
		uci_add_list "system.ntp.server" "$host"
	done
	apply_changes system
}


## @fn add_banner_event()
## @brief Füge ein Ereignis zum dauerhaften Ereignisprotokoll (/etc/banner) hinzu.
## @param event Ereignistext
## @param timestamp [optional] Der Zeitstempel-Text kann bei Bedarf vorgegeben werden.
## @details Ein Zeitstempel, sowie hübsche Formatierung wird automatisch hinzugefügt.
add_banner_event() {
	trap "error_trap add_banner_event '$*'" $GUARD_TRAPS
	local event=$1
	# verwende den optionalen zweiten Parameter oder den aktuellen Zeitstempel
	local timestamp="${2:-$(date)}"
	local line=" - $timestamp - $event -"
	(
		# Steht unser Text schon im Banner? Ansonsten hinzufuegen ...
		# bis einschliesslich Version v0.5.0 war "clean_restart_log" das Schluesselwort
		# ab v0.5.1 verwenden wir "system events"
		if ! grep -qE '(clean_restart_log|system events)' /etc/banner; then
			echo " ------------------- system events -------------------"
		fi
		# die Zeile auffuellen
		while [ "${#line}" -lt 54 ]; do line="$line-"; done
		echo "$line"
	) >>/etc/banner
	sync
}


clean_restart_log() {
	awk '{if ($1 != "-") print}' /etc/banner >/tmp/banner
	mv /tmp/banner /etc/banner
	sync
}


## @fn _get_file_dict_value()
## @brief Auslesen eines Werts aus einer Schlüssel/Wert-Datei
## @param status_file der Name der Schlüssel/Wert-Datei
## @param field das Schlüsselwort
## @returns Den zum gegebenen Schlüssel gehörenden Wert aus der Schlüssel/Wert-Datei.
##   Falls kein passender Schlüssel gefunden wurde, dann ist die Ausgabe leer.
## @details Jede Zeile dieser Datei enthält einen Feldnamen und einen Wert - beide sind durch
##   ein beliebiges whitespace-Zeichen getrennt.
##   Dieses Dateiformat wird beispielsweise für die Dienst-Zustandsdaten verwendet.
##   Zusätzlich ist diese Funktion auch zum Parsen von openvpn-Konfigurationsdateien geeignet.
_get_file_dict_value() { local key="$1"; shift; sed -n "s/^$key[ \t]\+//p" "$@" 2>/dev/null || true; }


## @fn _get_file_dict_keys()
## @brief Liefere alle Schlüssel aus einer Schlüssel/Wert-Datei.
## @param status_files Namen der Schlüssel/Wert-Dateien
## @returns Liste aller Schlüssel aus der Schlüssel/Wert-Datei.
## @sa _get_file_dict_value
_get_file_dict_keys() { sed 's/[ \t].*//' "$@" 2>/dev/null || true; }


## @fn _set_file_dict_value()
## @brief Schreiben eines Werts in eine Schlüssel/Wert-Datei
## @param status_file der Name der Schlüssel/Wert-Datei
## @param field das Schlüsselwort
## @param value der neue Wert
## @sa _get_file_dict_value
_set_file_dict_value() {
	local status_file=$1
	local field=$2
	local new_value=$3
	local fieldname
	local value=$(_get_file_dict_value "$field" "$status_file")
	# Wert ist korrekt? Wir sind fertig ...
	[ "$value" = "$new_value" ] && return 0
	# Filtere bisherige Zeilen mit dem key heraus.
	# Fuege anschliessend die Zeile mit dem neuen Wert an.
	# Die Sortierung sorgt fuer gute Vergleichbarkeit, um die Anzahl der
	# Schreibvorgaenge (=Wahrscheinlichkeit von gleichzeitigem Zugriff) zu reduzieren.
	(
		grep -v -w -s "$field" "$status_file"
		echo "$field $new_value"
	) | sort | update_file_if_changed "$status_file" || true
}


## @fn get_on_core_default()
## @brief Liefere einen der default-Werte der aktuellen Firmware zurück (Paket on-core).
## @param key Name des Schlüssels
## @details Die default-Werte werden nicht von der Konfigurationsverwaltung uci verwaltet.
##   Somit sind nach jedem Upgrade imer die neuesten Standard-Werte verfügbar.
get_on_core_default() {
	_get_file_dict_value "$1" "$ON_CORE_DEFAULTS_FILE"
}


## @fn get_on_firmware_version()
## @brief Liefere die aktuelle Firmware-Version zurück.
## @returns Die zurückgelieferte Zeichenkette beinhaltet den Versionsstring (z.B. "0.5.0").
## @details Per Konvention entspricht die Version jedes Firmware-Pakets der Firmware-Version.
get_on_firmware_version() {
	opkg status on-core | awk '{if (/Version/) print $2;}'
}


## @fn get_on_ip()
## @param on_id die ID des AP - z.B. "1.96" oder "2.54"
## @param on_ipschema siehe "get_on_core_default on_ipschema"
## @param interface_number 0..X (das WLAN-Interface ist typischerweise Interface #0)
## @attention Manche Aufrufende verlassen sich darauf, dass *on_id_1* und
##   *on_id_2* nach dem Aufruf verfügbar sind (also _nicht_ als "local"
##   Variablen deklariert wurden).
get_on_ip() {
	local on_id=$1
	local on_ipschema=$2
	local no=$3
	echo "$on_id" | grep -q "\." || on_id=1.$on_id
	on_id_1=$(echo "$on_id" | cut -d . -f 1)
	on_id_2=$(echo "$on_id" | cut -d . -f 2)
	echo $(eval echo $on_ipschema)
}


## @fn get_main_ip()
## @brief Liefere die aktuell konfigurierte Main-IP zurück.
## @returns Die aktuell konfigurierte Main-IP des AP oder die voreingestellte IP.
## @attention Seiteneffekt: die Variablen "on_id_1" und "on_id_2" sind anschließend verfügbar.
## @sa get_on_ip
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
	local pid_file=$1
	[ -e "$pid_file" ] || return 0
	local pid=$(cat "$pid_file" | sed 's/[^0-9]//g')
	[ -z "$pid" ] && msg_debug "removing broken PID file: $pid_file" && rm "$pid_file" && return 0
	[ ! -e "/proc/$pid" ] && msg_debug "removing stale PID file: $pid_file" && rm "$pid_file" && return 0
	return 0
}


# Pruefe ob eine PID-Datei existiert und ob die enthaltene PID zu einem Prozess
# mit dem angegebenen Namen (nur Dateiname - ohne Pfad) verweist.
# Parameter PID-Datei: vollstaendiger Pfad
# Parameter Prozess-Name: Dateiname ohne Pfad
check_pid_file() {
	trap "error_trap check_pid_file '$*'" $GUARD_TRAPS
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
			# TODO: verwenden wir ueberhaupt eine uci-Konfiguration?
			/etc/init.d/openvpn reload || true
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
	trap "error_trap set_opennet_id '$*'" $GUARD_TRAPS
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
	if is_function_available "get_on_wifidog_default"; then
		ipschema=$(get_on_wifidog_default free_ipschema)
		netmask=$(get_on_wifidog_default free_netmask)
		free_ipaddr=$(get_on_ip "$new_id" "$ipschema" 0)
		uci_prefix="network.$NETWORK_FREE"
		uci set "${uci_prefix}=interface"
		uci set "${uci_prefix}.proto=static"
		uci set "${uci_prefix}.ipaddr=$free_ipaddr"
		uci set "${uci_prefix}.netmask=$netmask"
	fi
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
# Der Separator ist konfigurierbar.
# Die Liste wird auf der Standardeingabe erwartet.
# Der erste und einzige Parameter ist der gewuenschte Schluessel.
get_from_key_value_list() {
	local search_key="$1"
	local separator="$2"
	local key_value
	local key
	sed 's/[ \t]\+/\n/g' | while read key_value; do
		key=$(echo "$key_value" | cut -f 1 -d "$separator")
		[ "$key" = "$search_key" ] && echo "$key_value" | cut -f 2- -d "$separator" && break || true
	done
	return 0
}


## @fn replace_in_key_value_list()
## @brief Ermittle aus einer mit Tabulatoren oder Leerzeichen getrennten Liste von Schlüssel-Wert-Paaren den Inhalt des Werts zu einem Schlüssel.
## @param search_key der Name des Schlüsselworts
## @param separator der Name des Trennzeichens zwischen Wert und Schlüssel
## @returns die korrigierte Schlüssel-Wert-Liste wird ausgegeben (eventuell mit veränderten Leerzeichen oder Tabulatoren)
replace_in_key_value_list() {
	local search_key="$1"
	local separator="$2"
	local value="$3"
	local key_value
	sed 's/[ \t]\+/\n/g' | while read key_value; do
		key=$(echo "$key_value" | cut -f 1 -d "$separator")
		if [ "$key" = "$search_key" ]; then
			# nicht ausgeben, falls der Wert leer ist
			[ -n "$value" ] && echo -n " ${key_value}${separator}${value}" || true
		else
			echo -n " $key_value"
		fi
	done | sed 's/^ //'
	return 0
}


# Wandle einen uebergebenene Parameter in eine Zeichenkette um, die sicher als Dateiname verwendet werden kann
get_safe_filename() {
	echo "$1" | sed 's/[^a-zA-Z0-9._\-]/_/g'
}


## @fn get_uptime_minutes()
## @brief Ermittle die seit dem Systemstart vergangene Zeit in Minuten
## @details Diese Zeit ist naturgemäß nicht für die Speicherung an Orten geeignet, die einen reboot überleben.
get_uptime_minutes() {
	awk '{print int($1/60)}' /proc/uptime
}


get_file_modification_timestamp_minutes() {
	local filename="$1"
	date --reference "$filename" +%s | awk '{ print int($1/60) }'
}


## @fn is_timestamp_older_minutes()
## @brief Prüfe, ob ein gegebener Zeitstempel älter ist, als die vorgegebene Zeitdifferenz.
## @param timestamp_minute der zu prüfende Zeitstempel (in Minuten seit dem Systemstart)
## @param difference zulässige Zeitdifferenz zwischen jetzt und dem Zeitstempel
## @returns Exitcode Null (Erfolg), falls der gegebene Zeitstempel mindestens 'difference' Minuten zurückliegt.
# Achtung: Zeitstempel aus der Zukunft gelten immer als veraltet.
is_timestamp_older_minutes() {
	local timestamp_minute="$1"
	local difference="$2"
	local now="$(get_uptime_minutes)"
	# it is older
	[ "$now" -ge "$((timestamp_minute+difference))" ] && return 0
	# timestamp in future -> invalid -> let's claim it is too old
	[ "$now" -lt "$timestamp_minute" ] && \
		msg_info "WARNING: Timestamp from future found: $timestamp_minute (minutes since epoch)" && \
		return 0
	trap "" $GUARD_TRAPS && return 1
}


## @fn get_uptime_seconds()
## @brief Ermittle die Anzahl der Sekunden seit dem letzten Bootvorgang.
get_uptime_seconds() {
	cut -f 1 -d . /proc/uptime
}


## @fn run_delayed_in_background()
## @brief Führe eine Aktion verzögert im Hintergrund aus.
## @param delay Verzögerung in Sekunden
## @param command alle weiteren Token werden als Kommando und Parameter interpretiert und mit Verzögerung ausgeführt.
run_delayed_in_background() {
	local delay="$1"
	shift
	(sleep "$delay" && "$@") </dev/null >/dev/null 2>&1 &
}


## @fn get_filesize()
## @brief Ermittle die Größe einer Datei in Bytes.
## @params filename Name der zu untersuchenden Datei.
get_filesize() {
	local filename="$1"
	wc -c "$filename" | awk '{ print $1 }'
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
	# 10) olsrd: ... olsrd_setup_smartgw_rules() Warning: kmod-ipip is missing.
	#    olsrd gibt beim Starten generell diese Warnung aus. Wir koennen sie ignorieren.
	filters="${filters}|olsrd.*olsrd_setup_smartgw_rules"
	# 11) olsrd: ... olsrd_write_interface() Warning: Interface '...' not found, skipped
	#    Falls das wlan-Interface beim Bootvorgang noch nicht aktiv ist, wenn olsrd startet, dann erscheint diese
	#    harmlose Meldung.
	filters="${filters}|olsrd.*Interface.*not found"
	# 12) dropbear[...]: Exit (root): Error reading: Connection reset by peer
	#    Verbindungsverlust einer ssh-Verbindung. Dies darf passieren.
	filters="${filters}|dropbear.*Connection reset by peer"
	# 13) cron-error: nc.*: short write
	#    Falls die Routen via nc während eines olsrd-Neustarts ausgelesen werden, reisst eventuell die Socket-
	#    Verbindung ab - dies ist akzeptabel.
	filters="${filters}|nc: short write"
	# 14) openvpn(___service_name___)[...]: write UDPv4: Network is unreachable
	#    Beispielsweise bei einem olsrd-Neustart reisst die Verbindung zum UGW-Server kurz ab.
	filters="${filters}|openvpn.*Network is unreachable"
	# 15) wget: can't connect to remote host
	#    Eine frühe Geschwindigkeitsmessung (kurz nach dem Booten) darf fehlschlagen.
	filters="${filters}|wget: can.t connect to remote host"
	# System-Fehlermeldungen (inkl. "trapped")
	logread | grep -i error | grep -vE "(${filters#|})" || true
}


# Im openwrt-Build-Prozess wird aus bisher ungeklaerter Ursache die falsche opkg-Repository-URL gesetzt.
# Diese Funktion erlaubt die einfache Aenderung der opkg-URL.
# Parameter: URL-Bestandteile (z.B. "stable/0.5.0")
set_opkg_download_version() {
	local version="$1"
	local opkg_file=/etc/opkg.conf
	local base_url=$(
		# importiere das DISTRIB_TARGET
		. /etc/openwrt_release
		# bei "ar71xx/generic" ignorieren wir den Teil nach dem slash - unsere Repo-Struktur hat diese Ebene nicht
		echo "http://downloads.on/openwrt/$version/${DISTRIB_TARGET%/generic}/packages"
	)
	# entferne Zeilen, die auf opennet-Domains verweisen
	(
		grep -vF "//downloads.on/" "$opkg_file" | grep -vF "//downloads.opennet-initiative.de/"
		echo "src/gz opennet $base_url/opennet"
	) | update_file_if_changed "$opkg_file" || true
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
	[ ! -e "$filename" ] && echo "$new_line" >"$filename" && return 0
	# Datei einlesen - zum Muster passende Zeilen austauschen - notfalls neue Zeile anfuegen
	(
		while read line; do
			echo "$line" | grep -q "$pattern" && echo "$new_line" || echo "$line"
		done <"$filename"
		# die neue Zeile hinzufuegen, falls das Muster in der alten Datei nicht vorhanden war
		grep -q "$pattern" "$filename" || echo "$new_line"
	) | update_file_if_changed "$filename" || true
}


## @fn is_package_installed()
## @brief Prüfe, ob ein opkg-Paket installiert ist.
## @param package Name des Pakets
is_package_installed() {
	local package="$1"
	opkg list-installed | grep -q "^$package[\t ]" && return 0
	trap "" $GUARD_TRAPS && return 1
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
	local func_name="$1"
	# "ash" liefert leider nicht den korrekten Wert "function" nach einem Aufruf von "type -t".
	# Also verwenden wir die Textausgabe von "type".
	# Die Fehlerausgabe von type wird ignoriert - im Falle der bash gibt es sonst unnoetige Ausgaben.
	type "$func_name" 2>/dev/null | grep -q "function$" && return 0
	trap "" $GUARD_TRAPS && return 1
}


## @fn get_local_bias_numer()
## @brief Ermittle eine lokale einzigartige Zahl, die als dauerhaft unveränderlich angenommen werden kann.
## @returns Eine (initial zufällig ermittelte) Zahl zwischen 0 und 10^8-1, die unveränderlich zu diesem AP gehört. 
## @details Für ein paar gleichrangige Sortierungen (z.B. verwendete
##   UGW-Gegenstellen) benötigen wir ein lokales Salz, um strukturelle
##   Bevorzugungen zu vermeiden.
get_local_bias_number() {
	trap "error_trap get_local_bias_number '$*'" $GUARD_TRAPS
	local bias=$(uci_get on-core.settings.local_bias_number)
	# der Bias-Wert ist schon vorhanden - wir liefern ihn aus
	if [ -z "$bias" ]; then
		# wir müssen einen Bias-Wert erzeugen: beliebige gehashte Inhalte ergeben eine akzeptable Zufallszahl
		bias=$( (logread; dmesg; ps; date) | md5sum | tr "abcdef" "012345" | cut -c 1-8)
		uci set "on-core.settings.local_bias_number=$bias"
		uci commit on-core
	fi
	echo -n "$bias" && return 0
}


## @fn system_service_check()
## @brief Prüfe ob ein Dienst läuft und ob seine PID-Datei aktuell ist.
## @param executable Der vollständige Pfad zu dem auszuführenden Programm.
## @param pid_file Der Name einer PID-Datei, die von diesem Prozess verwaltet wird.
## @deteils Dabei wird die 'service_check'-Funktion aus der openwrt-Shell-Bibliothek genutzt.
system_service_check() {
	local executable="$1"
	local pid_file="$2"
	. /lib/functions/service.sh
	SERVICE_PID_FILE="$pid_file"
	set +eu
	service_check "$executable" && return 0
	trap "" $GUARD_TRAPS && return 1
}


## @fn get_memory_size()
## @brief Ermittle die Größe des Arbeitsspeichers in Megabyte.
## @returns Der Rückgabewert (in Megabyte) ist etwas kleiner als der physische Arbeitsspeicher (z.B. 126 statt 128 MB).
get_memory_size() {
	local memsize_kb=$(grep "^MemTotal:" /proc/meminfo | sed 's/[^0-9]//g')
	echo $((memsize_kb / 1024))
}


run_parts() {
	trap "error_trap run_parts '$*'" $GUARD_TRAPS
	local rundir="$1"
	local fname
	# Abbruch, falls es das Verzeichnis nicht gibt
	[ -e "$rundir" ] || return 0
	find "$rundir" -maxdepth 1 | while read fname; do
		# ignoriere verwaiste symlinks
		[ ! -f "$fname" ] && continue
		msg_debug "on-run-parts: executing $fname"
		# ignoriere Fehler bei der Ausfuehrung
		"$fname" || true
	done
}

# Ende der Doku-Gruppe
## @}
