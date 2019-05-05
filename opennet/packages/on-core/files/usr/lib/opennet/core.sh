## @defgroup core Kern
## @brief Logging, Datei-Operationen, DNS- und NTP-Dienste, Dictionary-Dateien, PID- und Lock-Behandlung, Berichte
# Beginn der Doku-Gruppe
## @{


# Quelldatei für Standardwerte des Kern-Pakets
ON_CORE_DEFAULTS_FILE="${IPKG_INSTROOT:-}/usr/share/opennet/core.defaults"
# Pfad zur dnsmasq-Server-Datei zur dynamischen Aktualisierung durch Dienste-Erkennung
DNSMASQ_SERVERS_FILE_DEFAULT="${IPKG_INSTROOT:-}/var/run/dnsmasq.servers"
# DNS-Suffix, das vorrangig von den via olsrd publizierten Nameservern ausgeliefert werden soll
INTERN_DNS_DOMAIN=on
# Dateiname für erstellte Zusammenfassungen
REPORTS_FILE="${IPKG_INSTROOT:-}/tmp/on_report.tar.gz"
# Basis-Verzeichnis für Log-Dateien
LOG_BASE_DIR="${IPKG_INSTROOT:-}/var/log"
# maximum length of message lines (logger seems to resctrict lines incl. timestamp to 512 characters)
LOG_MESSAGE_LENGTH=420
# Verzeichnis für auszuführende Aktionen
SCHEDULING_DIR="${IPKG_INSTROOT:-}/var/run/on-scheduling.d"
# beim ersten Pruefen wird der Debug-Modus ermittelt
DEBUG_ENABLED=
# Notfall-DNS-Eintrag, falls wir noch keine nameservice-Nachrichten erhalten haben
# aktuelle UGW-Server, sowie der DNS-Server von FoeBuD (https://digitalcourage.de/support/zensurfreier-dns-server)
FALLBACK_DNS_SERVERS="192.168.0.246 192.168.0.247 192.168.0.248 85.214.20.141"
# fuer Insel-UGWs benoetigen wir immer einen korrekten NTP-Server, sonst schlaegt die mesh-Verbindung fehl
# aktuelle UGW-Server, sowie der openwrt-Pool
FALLBACK_NTP_SERVERS="192.168.0.246 192.168.0.247 192.168.0.248 0.openwrt.pool.ntp.org"
CRON_LOCK_FILE=/var/run/on-cron.lock
CRON_LOCK_MAX_AGE_MINUTES=15
CRON_LOCK_WAIT_TIMEOUT_SECONDS=30


# Aufteilung ueberlanger Zeilen
_split_lines() {
	local line_length="$1"
	# ersetze alle whitespace-Zeichen durch Nul
	# Gib anschliessend soviele Token wie moeglich aus, bis die Zeilenlaenge erreicht ist.
	tr '\n\t ' '\0' | xargs -0 -s "$line_length" echo
}


## @fn msg_debug()
## @param message Debug-Nachricht
## @brief Debug-Meldungen ins syslog schreiben
## @details Die Debug-Nachrichten landen im syslog (siehe ``logread``).
## Falls das aktuelle Log-Level bei ``info`` oder niedriger liegt, wird keine Nachricht ausgegeben.
msg_debug() {
	# bei der ersten Ausfuehrung dauerhaft speichern
	[ -z "$DEBUG_ENABLED" ] && \
		DEBUG_ENABLED=$(uci_is_true "$(uci_get on-core.settings.debug false)" && echo 1 || echo 0)
	[ "$DEBUG_ENABLED" = "0" ] || echo "$1" | _split_lines "$LOG_MESSAGE_LENGTH" | logger -t "$(basename "$0")[$$]"
}


## @fn msg_info()
## @param message Log-Nachricht
## @brief Informationen und Fehlermeldungen ins syslog schreiben
## @details Die Nachrichten landen im syslog (siehe ``logread``).
## Die info-Nachrichten werden immer ausgegeben, da es kein höheres Log-Level als "debug" gibt.
msg_info() {
	echo "$1" | _split_lines "$LOG_MESSAGE_LENGTH" | logger -t "$(basename "$0")[$$]"
}


## @fn msg_error()
## @param message Fehlermeldung
## @brief Die Fehlermeldungen werden in die Standard-Fehlerausgabe und ins syslog geschrieben
## @details Jede Meldung wird mit "ERROR" versehen, damit diese Meldungen von
##   "get_potential_error_messages" erkannt werden.
## Die error-Nachrichten werden immer ausgegeben, da es kein höheres Log-Level als "debug" gibt.
msg_error() {
	echo "$1" | _split_lines "$LOG_MESSAGE_LENGTH" | logger -s -t "$(basename "$0")[$$]" "[ERROR] $1"
}


## @fn append_to_custom_log()
## @param log_name Name des Log-Ziels
## @param event die Kategorie der Meldung (up/down/???)
## @param msg die textuelle Beschreibung des Ereignis (z.B. "connection with ... closed")
## @brief Hänge eine neue Nachricht an ein spezfisches Protokoll an.
## @details Die Meldungen werden beispielsweise von den konfigurierten openvpn-up/down-Skripten gesendet.
append_to_custom_log() {
	local log_name="$1"
	local event="$2"
	local msg="$3"
	local logfile
	logfile=$(get_custom_log_filename "$log_name")
	echo "$(date) openvpn [$event]: $msg" >>"$logfile"
	# Datei kuerzen, falls sie zu gross sein sollte
	local filesize
	filesize=$(get_filesize "$logfile")
	[ "$filesize" -gt 10000 ] && sed -i "1,30d" "$logfile"
	return 0
}


## @fn get_custom_log_filename()
## @param log_name Name des Log-Ziels
## @brief Liefere den Inhalt eines spezifischen Logs (z.B. das OpenVPN-Verbindungsprotokoll) zurück.
## @returns Zeilenweise Ausgabe der Protokollereignisse (aufsteigend nach Zeitstempel sortiert).
get_custom_log_filename() {
	local log_name="$1"
	# der Aufrufer darf sich darauf verlassen, dass er in die Datei schreiben kann
	mkdir -p "$LOG_BASE_DIR"
	echo "$LOG_BASE_DIR/${log_name}.log"
}


## @fn get_custom_log_content()
## @param log_name Name des Log-Ziels
## @brief Liefere den Inhalt eines spezifischen Logs (z.B. das OpenVPN-Verbindungsprotokoll) zurück.
## @returns Zeilenweise Ausgabe der Protokollereignisse (aufsteigend nach Zeitstempel sortiert).
get_custom_log_content() {
	local log_name="$1"
	local logfile
	logfile=$(get_custom_log_filename "$log_name")
	[ -e "$logfile" ] || return 0
	cat "$logfile"
}


## @fn update_file_if_changed()
## @param target_filename Name der Zieldatei
## @brief Aktualisiere eine Datei, falls sich ihr Inhalt geändert haben sollte.
## @details Der neue Inhalt der Datei wird auf der Standardeingabe erwartet.
##   Im Falle der Gleichheit von aktuellem Inhalt und zukünftigem Inhalt wird
##   keine Schreiboperation ausgeführt. Der Exitcode gibt an, ob eine Schreiboperation
##   durchgeführt wurde.
## @return exitcode=0 (Erfolg) falls die Datei geändert werden musste
## @return exitcode=1 (Fehler) falls es keine Änderung gab
update_file_if_changed() {
	local target_filename="$1"
	local content
	content="$(cat -)"
	if [ -e "$target_filename" ] && echo "$content" | cmp -s - "$target_filename"; then
		# the content did not change
		trap "" EXIT && return 1
	else
		# updated content
		local dirname
		dirname=$(dirname "$target_filename")
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
	trap 'error_trap update_dns_servers "$*"' EXIT
	local host
	local port
	local service
	# wenn wir eine VPN-Tunnel-Verbindung aufgebaut haben, sollten wir DNS-Anfragen über diese Crypto-Verbindung lenken
	local preferred_servers
	local use_dns
	use_dns=$(uci_get on-core.settings.use_olsrd_dns)
	# return if we should not use DNS servers provided via olsrd
	uci_is_false "$use_dns" && return 0
	local servers_file
	local server_config
	servers_file=$(uci_get "dhcp.@dnsmasq[0].serversfile")
	# aktiviere die "dnsmasq-serversfile"-Direktive, falls noch nicht vorhanden
	if [ -z "$servers_file" ]; then
		servers_file="$DNSMASQ_SERVERS_FILE_DEFAULT"
		uci set "dhcp.@dnsmasq[0].serversfile=$servers_file"
		uci commit "dhcp.@dnsmasq[0]"
		reload_config
	fi
	preferred_servers=$(if is_function_available "get_mig_tunnel_servers"; then get_mig_tunnel_servers "DNS"; fi)
	# wir sortieren alphabetisch - Naehe ist uns egal
	server_config=$(
		get_services "dns" | filter_reachable_services | filter_enabled_services | sort | while read -r service; do
			host=$(get_service_value "$service" "host")
			port=$(get_service_value "$service" "port")
			[ -n "$port" ] && [ "$port" != "53" ] && host="$host#$port"
			# Host nur schreiben, falls kein bevorzugter Host gefunden wurde
			[ -z "$preferred_servers" ] && echo "server=$host"
			# Die interne Domain soll vorranging von den via olsrd verbreiteten DNS-Servern bedient werden.
			# Dies ist vor allem fuer UGW-Hosts wichtig, die über eine zweite DNS-Quelle (lokaler uplink)
			# verfügen.
			echo "server=/$INTERN_DNS_DOMAIN/$host"
		done
		# eventuell bevorzugte Hosts einfuegen
		for host in $preferred_servers; do
			echo "server=$host"
		done
	)
	# falls keine DNS-Namen bekannt sind, dann verwende eine (hoffentlich gueltige) Notfall-Option
	[ -z "$server_config" ] && server_config=$(echo "$FALLBACK_DNS_SERVERS" | tr ' ' '\n' | sed 's/^/server=/')
	echo "$server_config" | update_file_if_changed "$servers_file" || return 0
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
	trap 'error_trap update_ntp_servers "$*"' EXIT
	local host
	local port
	local service
	local preferred_servers
	local previous_entries
	local use_ntp
	previous_entries=$(uci_get "system.ntp.server")
	use_ntp=$(uci_get "on-core.settings.use_olsrd_ntp")
	# return if we should not use NTP servers provided via olsrd
	uci_is_false "$use_ntp" && return
	preferred_servers=$(if is_function_available "get_mig_tunnel_servers"; then get_mig_tunnel_servers "NTP"; fi)
	# schreibe die Liste der NTP-Server neu
	# wir sortieren alphabetisch - Naehe ist uns egal
	if [ -n "$preferred_servers" ]; then
		for host in $preferred_servers; do
			echo "$host"
		done
	else
		get_services "ntp" | filter_reachable_services | filter_enabled_services | sort | while read -r service; do
			host=$(get_service_value "$service" "host")
			port=$(get_service_value "$service" "port")
			[ -n "$port" ] && [ "$port" != "123" ] && host="$host:$port"
			echo "$host"
		done
	fi | uci_replace_list "system.ntp.server"
	# Wir wollen keine leere Liste zurücklassen (z.B. bei einem UGW ohne Mesh-Anbindung).
	# Also alte Werte wiederherstellen, sowie zusaetzlich die default-Server.
	# Vor allem fuer den https-Download der UGW-Server-Liste benoetigen wir eine korrekte Uhrzeit.
	[ -z "$(uci_get "system.ntp.server")" ] && \
		for host in $previous_entries $FALLBACK_NTP_SERVERS; do uci_add_list "system.ntp.server" "$host"; done
	apply_changes system
}


## @fn add_banner_event()
## @param event Ereignistext
## @param timestamp [optional] Der Zeitstempel-Text kann bei Bedarf vorgegeben werden.
## @brief Füge ein Ereignis zum dauerhaften Ereignisprotokoll (/etc/banner) hinzu.
## @details Ein Zeitstempel, sowie hübsche Formatierung wird automatisch hinzugefügt.
add_banner_event() {
	trap 'error_trap add_banner_event "$*"' EXIT
	local event="$1"
	# verwende den optionalen zweiten Parameter oder den aktuellen Zeitstempel
	local timestamp="${2:-}"
	[ -z "$timestamp" ] && timestamp=$(date)
	local line=" - $timestamp - $event -"
	# Steht unser Text schon im Banner? Ansonsten hinzufuegen ...
	# bis einschliesslich Version v0.5.0 war "clean_restart_log" das Schluesselwort
	# ab v0.5.1 verwenden wir "system events"
	if ! grep -qE '(clean_restart_log|system events)' /etc/banner; then
		echo " ------------------- system events -------------------" >>/etc/banner
	fi
	# die Zeile auffuellen
	while [ "${#line}" -lt 54 ]; do line="$line-"; done
	echo "$line" >>/etc/banner
	sync
}


## @fn update_mesh_interfaces()
## @brief Update mesh interfaces, routing daemons and policy routing
## @details This function should be called whenever the list of interfaces changes.
update_mesh_interfaces() {
	update_olsr_interfaces
	if is_function_available update_olsr2_interfaces; then
		update_olsr2_interfaces
	fi
}


## @fn clean_restart_log()
## @brief Alle Log-Einträge aus der banner-Datei entfernen.
clean_restart_log() {
	awk '{if ($1 != "-") print}' /etc/banner >/tmp/banner
	mv /tmp/banner /etc/banner
	sync
}


## @fn _get_file_dict_value()
## @param key das Schlüsselwort
## @brief Auslesen eines Werts aus einem Schlüssel/Wert-Eingabestrom
## @returns Den zum gegebenen Schlüssel gehörenden Wert aus dem Schlüssel/Wert-Eingabestrom
##   Falls kein passender Schlüssel gefunden wurde, dann ist die Ausgabe leer.
## @details Jede Zeile der Standardeingabe enthält einen Feldnamen und einen Wert - beide sind durch
##   ein beliebiges whitespace-Zeichen getrennt.
##   Dieses Dateiformat wird beispielsweise für die Dienst-Zustandsdaten verwendet.
##   Zusätzlich ist diese Funktion auch zum Parsen von openvpn-Konfigurationsdateien geeignet.
_get_file_dict_value() { local key="$1"; shift; { grep "^$key[[:space:]]" "$@" 2>/dev/null || true; } | while read -r key value; do echo -n "$value"; done; }


## @fn _get_file_dict_keys()
## @brief Liefere alle Schlüssel aus einem Schlüssel/Wert-Eingabestrom.
## @returns Liste aller Schlüssel aus dem Schlüssel/Wert-Eingabestrom.
## @sa _get_file_dict_value
_get_file_dict_keys() { sed 's/[ \t].*//' "$@" 2>/dev/null || true; }


## @fn _set_file_dict_value()
## @param field das Schlüsselwort
## @param value der neue Wert
## @brief Ersetzen oder Einfügen eines Werts in einen Schlüssel/Wert-Eingabestrom.
## @sa _get_file_dict_value
_set_file_dict_value() {
	local status_file="$1"
	local field="$2"
	local new_value="$3"
	[ -z "$field" ] && msg_error "Ignoring empty key for _set_file_dict_value" && return
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
## @param key Name des Schlüssels
## @brief Liefere einen der default-Werte der aktuellen Firmware zurück (Paket on-core).
## @details Die default-Werte werden nicht von der Konfigurationsverwaltung uci verwaltet.
##   Somit sind nach jedem Upgrade imer die neuesten Standard-Werte verfügbar.
get_on_core_default() {
	local key="$1"
	_get_file_dict_value "$key" "$ON_CORE_DEFAULTS_FILE"
}


## @fn get_on_firmware_version()
## @brief Liefere die aktuelle Firmware-Version zurück.
## @returns Die zurückgelieferte Zeichenkette beinhaltet den Versionsstring (z.B. "0.5.0").
## @details Per Konvention entspricht die Version jedes Firmware-Pakets der Firmware-Version.
##   Um locking-Probleme zu vermeiden, lesen wir den Wert direkt aus der control-Datei des Pakets.
##   Das ist nicht schoen - aber leider ist die lock-Datei nicht konfigurierbar.
get_on_firmware_version() {
	trap 'error_trap get_on_firmware_version "$*"' EXIT
	local status_file="${IPKG_INSTROOT:-}/usr/lib/opkg/info/on-core.control"
	[ -e "$status_file" ] || return 0
	awk '{if (/^Version:/) print $2;}' <"$status_file"
}


## @fn get_on_firmware_version_new()
get_on_firmware_version_new() {
	trap 'error_trap get_on_firmware_version_new "$*"' EXIT

	local config_seed
	config_seed=$(https_request_opennet https://downloads.opennet-initiative.de/openwrt/testing/latest/targets/ar71xx/generic/config.seed)
	echo "$config_seed" | grep ^CONFIG_VERSION_NUMBER | sed 's/CONFIG_VERSION_NUMBER="\(.*\)".*/\1/'
}


## @fn check_new_on_firmware_version_new()
check_new_on_firmware_version_new() {
	trap 'error_trap check_new_on_firmware_version_new "$*"' EXIT

	local old_version
	local new_version
	old_version=$(get_on_firmware_version | cut -d '-' -f 3)
	new_version=$(get_on_firmware_version_new | cut -d '-' -f 3)

	if [ "$old_version" != "$new_version" ]; then
		return 0
	else
		trap "" EXIT && return 1
	fi
}


get_openwrt_arch() {
	trap 'error_trap get_openwrt_arch "$*"' EXIT

	(. /etc/openwrt_release; echo "$DISTRIB_TARGET")
}


## @fn get_on_ip()
## @param on_id die ID des AP - z.B. "1.96" oder "2.54"
## @param on_ipschema siehe "get_on_core_default on_ipschema"
## @param interface_number 0..X (das WLAN-Interface ist typischerweise Interface #0)
## @attention Manche Aufrufende verlassen sich darauf, dass *on_id_1* und
##   *on_id_2* nach dem Aufruf verfügbar sind (also _nicht_ als "local"
##   Variablen deklariert wurden).
get_on_ip() {
	local on_id="$1"
	local on_ipschema="$2"
	local interface_number="$3"
	local on_id_1
	local on_id_2
	# das "on_ipschema" erwartet die Variable "no"
	# shellcheck disable=SC2034
	local no="$interface_number"
	echo "$on_id" | grep -q '\.' || on_id=1.$on_id
	# shellcheck disable=SC2034
	on_id_1=$(echo "$on_id" | cut -d . -f 1)
	# shellcheck disable=SC2034
	on_id_2=$(echo "$on_id" | cut -d . -f 2)
	eval echo "$on_ipschema"
}


## @fn get_main_ip()
## @brief Liefere die aktuell konfigurierte Main-IP zurück.
## @returns Die aktuell konfigurierte Main-IP des AP oder die voreingestellte IP.
## @attention Seiteneffekt: die Variablen "on_id_1" und "on_id_2" sind anschließend verfügbar.
## @sa get_on_ip
get_main_ip() {
	local on_id
	local ipschema
	on_id=$(uci_get on-core.settings.on_id "$(get_on_core_default on_id_preset)")
	ipschema=$(get_on_core_default on_ipschema)
	get_on_ip "$on_id" "$ipschema" 0
}


## @fn run_with_cron_lock()
## @details Führe eine Aktion aus, falls das Lock für Cron-Jobs übernommen werden konnte
## @params command alle Parameter werden als auszuführendes Kommando interpretiert
run_with_cron_lock() {
	local returncode
	# Der Timeout ist nötig, weil alle cron-Jobs gleichzeitig gestartet werden. Somit treffen
	# der minütige und der fünf-minütige cron-Job aufeinandern und möchten dasselbe Lock
	# halten. Die maximale Wartezeit löst wahrscheinlich die meisten Konflikte.
	if acquire_lock "$CRON_LOCK_FILE" "$CRON_LOCK_MAX_AGE_MINUTES" "$CRON_LOCK_WAIT_TIMEOUT_SECONDS"; then
		set +e
		"$@"
		returncode=$?
		set -e
		rm -f "$CRON_LOCK_FILE"
		return "$returncode"
	fi
}


is_lock_available() {
	local lock_file="$1"
	local max_age_minutes="$2"
	# Fehlerfall: die Lock-Datei existiert und ist nicht alt genug
	[ ! -e "$lock_file" ] || is_file_timestamp_older_minutes "$lock_file" "$max_age_minutes"
}


## @fn acquire_lock()
## @brief Prüfe ob eine Lock-Datei existiert und nicht veraltet ist.
## @details Die folgenden Zustände werden behandelt:
##    A) die Datei existiert, ist jedoch veraltet -> Erfolg, Zeitstempel der Datei aktualisieren
##    B) die Datei existiert und ist noch nicht veraltet -> Fehlschlag
##    C) die Datei existiert nicht -> Erfolg, Datei wird angelegt
##    Warte notfalls einen Timeout ab, bis das Lock frei wird.
## @returns Erfolg (Lock erhalten) oder Misserfolg (Lock ist bereits vergeben)
acquire_lock() {
	local lock_file="$1"
	local max_age_minutes="$2"
	local timeout="$3"
	local timeout_limit
	timeout_limit=$(( $(date +%s) + timeout ))
	while ! is_lock_available "$lock_file" "$max_age_minutes"; do
		if [ "$(date +%s)" -ge "$timeout_limit" ]; then
			msg_info "Failed to acquire lock file: $lock_file"
			trap "" EXIT && return 1
		fi
		sleep "$(( $(get_random 10) + 1 ))"
	done
	touch "$lock_file"
	return 0
}


# Pruefe ob eine PID-Datei existiert und ob die enthaltene PID zu einem Prozess
# mit dem angegebenen Namen (nur Dateiname - ohne Pfad) verweist.
# Parameter PID-Datei: vollstaendiger Pfad
# Parameter Prozess-Name: Dateiname ohne Pfad
check_pid_file() {
	trap 'error_trap check_pid_file "$*"' EXIT
	local pid_file="$1"
	local process_name="$2"
	local pid
	local current_process
	if [ -z "$pid_file" ] || [ ! -e "$pid_file" ]; then trap "" EXIT && return 1; fi
	pid=$(sed 's/[^0-9]//g' "$pid_file")
	# leere/kaputte PID-Datei
	[ -z "$pid" ] && trap "" EXIT && return 1
	# Prozess-Datei ist kein symbolischer Link?
	[ ! -L "/proc/$pid/exe" ] && trap "" EXIT && return 1
	current_process=$(readlink "/proc/$pid/exe")
	[ "$process_name" != "$(basename "$current_process")" ] && trap "" EXIT && return 1
	return 0
}


## @fn apply_changes()
## @param configs Einer oder mehrere uci-Sektionsnamen.
## @brief Kombination von uci-commit und anschliessender Inkraftsetzung fuer verschiedene uci-Sektionen.
## @details Dienst-, Netzwerk- und Firewall-Konfigurationen werden bei Bedarf angewandt.
##   Zuerst werden alle uci-Sektionen commited und anschliessend werden die Trigger ausgefuehrt.
apply_changes() {
	local config
	# Zuerst werden alle Änderungen committed und anschließend die (veränderten) Konfiguration
	# für den Aufruf der hook-Skript verwandt.
	for config in "$@"; do
		# Opennet-Module achten auch auf nicht-uci-Aenderungen
		if echo "$config" | grep -q "^on-"; then
			uci -q commit "$config" || true
			echo "$config"
		elif [ -z "$(uci -q changes "$config")" ]; then
			# keine Aenderungen?
			true
		else
			uci commit "$config"
			echo "$config"
		fi
	done | grep -v "^$" | sort | uniq | while read -r config; do
		run_parts "${IPKG_INSTROOT:-}/usr/lib/opennet/hooks.d" "$config"
	done
	return 0
}


# Setzen einer Opennet-ID.
# 1) Hostnamen setzen
# 2) IPs fuer alle Opennet-Interfaces setzen
# 3) Main-IP in der olsr-Konfiguration setzen
# 4) IP des Interface "free" setzen
set_opennet_id() {
	trap 'error_trap set_opennet_id "$*"' EXIT
	local new_id="$1"
	local network
	local uci_prefix
	local ipaddr
	local main_ipaddr
	local ipschema
	local netmask
	local if_counter=0
	# ID normalisieren (AP7 -> AP1.7)
	echo "$new_id" | grep -q '\.' || new_id=1.$new_id
	# ON_ID in on-core-Settings setzen
	prepare_on_uci_settings
	uci set "on-core.settings.on_id=$new_id"
	apply_changes on-core
	# Hostnamen konfigurieren
	find_all_uci_sections system system | while read -r uci_prefix; do
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
		if_counter=$((if_counter + 1))
	done
	# OLSR-MainIP konfigurieren
	olsr_set_main_ip "$main_ipaddr"
	apply_changes olsrd network
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
	{ sed 's/[ \t]\+/\n/g'; echo; } | while read -r key_value; do
		key=$(echo "$key_value" | cut -f 1 -d "$separator")
		[ "$key" = "$search_key" ] && echo "$key_value" | cut -f 2- -d "$separator" && break
		true
	done
	return 0
}


## @fn replace_in_key_value_list()
## @param search_key der Name des Schlüsselworts
## @param separator der Name des Trennzeichens zwischen Wert und Schlüssel
## @brief Ermittle aus einer mit Tabulatoren oder Leerzeichen getrennten Liste von Schlüssel-Wert-Paaren den Inhalt des Werts zu einem Schlüssel.
## @returns die korrigierte Schlüssel-Wert-Liste wird ausgegeben (eventuell mit veränderten Leerzeichen oder Tabulatoren)
replace_in_key_value_list() {
	local search_key="$1"
	local separator="$2"
	local value="$3"
	awk 'BEGIN { found=0; FS="'"$separator"'"; OFS=":"; RS="[ \t]"; ORS=" "; }
		{ if ($1 == "'"$search_key"'") { print "'"$search_key"'", '"$value"'; found=1; } else { print $0; } }
		END { if (found == 0) print "'"$search_key"'", '"$value"' };'
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


## @fn is_file_timestamp_older_minutes()
## @brief Prüfe ob die Datei älter ist als die angegebene Zahl von Minuten.
## @details Alle Fehlerfälle (Datei existiert nicht, Zeitstempel liegt in der Zukunft, ...) werden
##   als "veraltet" gewertet.
## @returns True, falls die Datei existiert und älter als angegeben ist - ansonsten "False"
is_file_timestamp_older_minutes() {
	trap 'error_trap is_file_timestamp_older_minutes "$*"' EXIT
	local filename="$1"
	local limit_minutes="$2"
	[ -e "$filename" ] || return 0
	local file_timestamp
	local timestamp_now
	file_timestamp=$(date --reference "$filename" +%s 2>/dev/null | awk '{ print int($1/60) }')
	# Falls die Datei zwischendurch geloescht wurde, ist das Lock nun frei.
	[ -z "$file_timestamp" ] && return 0
	timestamp_now=$(date +%s | awk '{ print int($1/60) }')
	# veraltet, falls:
	#   * kein Zeitstempel
	#   * Zeitstempel in der Zukunft
	#   * Zeitstempel älter als erlaubt
	if [ -z "$file_timestamp" ] \
			|| [ "$file_timestamp" -gt "$timestamp_now" ] \
			|| [ "$((file_timestamp + limit_minutes))" -lt "$timestamp_now" ]; then
		return 0
	else
		trap "" EXIT && return 1
	fi
}


## @fn is_timestamp_older_minutes()
## @param timestamp_minute der zu prüfende Zeitstempel (in Minuten seit dem Systemstart)
## @param difference zulässige Zeitdifferenz zwischen jetzt und dem Zeitstempel
## @brief Prüfe, ob ein gegebener Zeitstempel älter ist, als die vorgegebene Zeitdifferenz.
## @returns Exitcode Null (Erfolg), falls der gegebene Zeitstempel mindestens 'difference' Minuten zurückliegt.
# Achtung: Zeitstempel aus der Zukunft oder leere Zeitstempel gelten immer als veraltet.
is_timestamp_older_minutes() {
	local timestamp_minute="$1"
	local difference="$2"
	[ -z "$timestamp_minute" ] && return 0
	local now
	now="$(get_uptime_minutes)"
	# it is older
	[ "$now" -ge "$((timestamp_minute + difference))" ] && return 0
	# timestamp in future -> invalid -> let's claim it is too old
	[ "$now" -lt "$timestamp_minute" ] && \
		msg_info "WARNING: Timestamp from future found: $timestamp_minute (minutes since epoch)" && \
		return 0
	trap "" EXIT && return 1
}


## @fn get_uptime_seconds()
## @brief Ermittle die Anzahl der Sekunden seit dem letzten Bootvorgang.
get_uptime_seconds() {
	cut -f 1 -d . /proc/uptime
}


## @fn run_delayed_in_background()
## @param delay Verzögerung in Sekunden
## @param command alle weiteren Token werden als Kommando und Parameter interpretiert und mit Verzögerung ausgeführt.
## @brief Führe eine Aktion verzögert im Hintergrund aus.
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
	trap 'error_trap generate_report "$*"' EXIT
	local fname
	local pid
	local reports_dir
	local temp_dir
	local tar_file
	temp_dir=$(mktemp -d)
	reports_dir="$temp_dir/report"
	tar_file=$(mktemp)
	msg_debug "Creating a report"
	# die Skripte duerfen davon ausgehen, dass wir uns im Zielverzeichnis befinden
	mkdir -p "$reports_dir"
	cd "$reports_dir"
	find /usr/lib/opennet/reports -type f | sort | while read -r fname; do
		[ ! -x "$fname" ] && msg_info "skipping non-executable report script: $fname" && continue
		"$fname" || msg_error "reports script failed: $fname"
	done
	# "tar" unterstuetzt "-c" nicht - also komprimieren wir separat
	tar cC "$temp_dir" "report" | gzip >"$tar_file"
	rm -r "$temp_dir"
	mv "$tar_file" "$REPORTS_FILE"
}


## @fn get_potential_error_messages()
## @param max_lines die Angabe einer maximalen Anzahl von Zeilen ist optional - andernfalls werden alle Meldungen ausgegeben
## @brief Filtere aus allen zugänglichen Quellen mögliche Fehlermeldungen.
## @details Falls diese Funktion ein nicht-leeres Ergebnis zurückliefert, kann dies als Hinweis für den
##   Nutzer verwendet werden, auf dass er einen Fehlerbericht einreicht.
get_potential_error_messages() {
	local max_lines="${1:-}"
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
	# 16) openvpn(...)[...]: Options error: Unrecognized option or missing parameter(s) in [PUSH-OPTIONS]:11: explicit-exit-notify (2.3.6)
	#    OpenVPN-Versionen, die ohne die "--extras"-Option gebaut wurden, unterstuetzen keine exit-Notification.
	#    Dies ist unproblematisch - es ist eher eine Sache der Höflichkeit..
	filters="${filters}|openvpn.*Options error.*explicit-exit-notify"
	# 17) ddns-scripts[...]: myddns_ipv4: ...
	#    ddns meldet leidet beim Starten einen Fehler, solange es unkonfiguriert ist.
	filters="${filters}|ddns-scripts.*myddns_ipv[46]"
	# 18) Collected errors:
	#    opkg-Paketinstallationen via Web-Interface erzeugen gelegentlich Fehlermeldungen (z.B. Entfernung
	#    abhängiger Pakete), die dem Nutzer im Web-Interface angezeigt werden. Diese Fehlermeldungen landen
	#    zusätzlich auch im log-Buffer. Da der Nutzer sie bereits gesehen haben dürfte, können wir sie ignorieren
	#    (zumal die konkreten Fehlermeldungen erst in den folgenden Zeilen zu finden und somit schlecht zu filtern
	#    sind).
	filters="${filters}|Collected errors:"
	# 19) uhttpd[...]: sh: write error: Broken pipe
	#    http-Requests die von seiten des Browser abgebrochen wurden
	filters="${filters}|uhttpd.*: sh: write error: Broken pipe"
	# 20) __main__ get_variable ...
	#    Der obige "Broken pipe"-Fehler unterbricht dabei auch die akuell laufende Funktion - dies ist
	#    sehr häufig die Variablen-Auslesung (seltsamerweise).
	filters="${filters}|__main__ get_variable "
	# 21) ERROR: Linux route add command failed
	#    Beim Aufbau er OpenVPN-Verbindung scheint gelegentlich noch eine alte Route verblieben zu sein.
	#    Diese Meldung ist wohl irrelevant.
	filters="${filters}|ERROR: Linux route add command failed"
	# 22) ... cannot open proc entry /proc/sys/net/ipv4/conf/none/ ...
	#    olsrd2 versucht auf /proc/-Eintraege zuzugreifen, bevor der Name des Netzwerk-Interface
	#    feststeht ("none"). Ignorieren.
	filters="${filters}|cannot open proc entry /proc/sys/net/ipv4/conf/none/"
	# 23) RTNETLINK answers: Network is unreachable
	#    bei einem OpenVPN-Verbindungsaufbau gehen die ersten Pakete verloren
	filters="${filters}|RTNETLINK answers: Network is unreachable"
	# 24) olsrd2: wrote '/var/run/olsrd2_dev'
	#    beim OLSRD2-Start wird diese Meldung auf stderr ausgegeben
	filters="${filters}|olsrd2: wrote .*olsrd2_dev"
	# 25) nl80211 not found
	#    Während der initialen wireless-Konfigurationsermittlung beim ersten Boot-Vorgang wird
	#    "iw" aufgerufen, auch wenn eventuell kein wifi-Interface vorhanden ist. In diesem Fall
	#    wird der obige Hinweis ausgegeben.
	filters="${filters}|nl80211 not found"
	# 26) OLSRd2[...]: WARN(os_interface) ...: Error, cannot open proc entry /proc/sys/net/ipv4/conf/on_wifi_1/... No such file or directory
	#    olsrd2 versucht auf /proc/-Eintraege mittels des Namens eines logischen
	#    Netzwerk-Interface (z.B. "on_eth_0") zuzugreifen, obwohl das System nur die physischen
	#    Interfaces kennt.
	filters="${filters}|cannot open proc entry /proc/sys/net/ipv4/conf/on_"
	# 27) OLSRd2[...]: WARN(os_interface) ...: WARNING! Could not disable the IP spoof filter
	#    Im Anschluss an den obigen (26) Fehlversuch, fuer ein logisches Netzwerk-Interface den
	#    rp_filter zu deaktivieren, wird diese Warnung ausgegeben. Sie ist nicht relevant.
	filters="${filters}"'|WARN\(os_interface\).*Could not disable (the IP spoof filter|ICMP redirects)'
	# System-Fehlermeldungen (inkl. "trapped")
	# Frühzeitig Broken-Pipe-Fehler ("uhttpd[...]: sh: write error: Broken pipe") sowie die darauffolgende
	# Zeile entfernen. Diese Fehler treten auf, wenn der Nutzer das Laden der Webseite unterbricht (z.B.
	# durch frühe Auswahl einer neuen URL).
	prefilter="uhttpd.*: sh: write error: Broken pipe"
	# "sed /FOO/{N;d;}" löscht die Muster-Zeile, sowie die direkt nachfolgende
	logread | sed "/$prefilter/{N;d;}" | grep -iE "(error|crash)" | grep -vE "(${filters#|})" | if [ -z "$max_lines" ]; then
		# alle Einträge ausgeben
		cat -
	else
		# nur die letzten Einträge ausliefern
		tail -n "$max_lines"
	fi
}


# Ersetze eine Zeile durch einen neuen Inhalt. Falls das Zeilenmuster nicht vorhanden ist, wird eine neue Zeile eingefuegt.
# Dies entspricht der Funktionalitaet des "lineinfile"-Moduls von ansible.
# Parameter filename: der Dateiname
# Parameter pattern: Suchmuster der zu ersetzenden Zeile
# Parameter new_line: neue Zeile
line_in_file() {
	trap 'error_trap line_in_file "$*"' EXIT
	local filename="$1"
	local pattern="$2"
	local new_line="$3"
	local line
	# Datei existiert nicht? Einfach mit dieser Zeile erzeugen.
	[ ! -e "$filename" ] && echo "$new_line" >"$filename" && return 0
	# Datei einlesen - zum Muster passende Zeilen austauschen - notfalls neue Zeile anfuegen
	(
		while read -r line; do
			if echo "$line" | grep -q "$pattern"; then
				[ -n "$new_line" ] && echo "$new_line"
				# die Zeile nicht erneut schreiben - alle zukuenftigen Vorkommen loeschen
				new_line=
			else
				echo "$line"
			fi
		done <"$filename"
		# die neue Zeile hinzufuegen, falls das Muster in der alten Datei nicht vorhanden war
		grep -q "$pattern" "$filename" || echo "$new_line"
	) | update_file_if_changed "$filename" || true
}


# Pruefe, ob eine Liste ein bestimmtes Element enthaelt
# Die Listenelemente sind durch beliebigen Whitespace getrennt.
is_in_list() {
	local target="$1"
	local list="$2"
	local token
	for token in $list; do
		[ "$token" = "$target" ] && return 0
		true
	done
	# kein passendes Token gefunden
	trap "" EXIT && return 1
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
	trap "" EXIT && return 1
}


## @fn get_random()
## @brief Liefere eine Zufallszahl innerhalb des gegebenen Bereichs.
## @returns Eine zufällige Ganzzahl.
get_random() {
	local range="$1"
	local random_number
	# Setze eine "1" vor eine zufällige Anzahl von Ziffern (vermeide Oktal-Zahl-Behandlung).
	# Begrenze die Anzahl von Ziffern, um Rundungen in awk zu vermeiden.
	random_number="1$(dd if=/dev/urandom bs=10 count=1 2>/dev/null | md5sum | tr -dc "0123456789" | cut -c 1-6)"
	printf "%d %d" "$range" "$random_number" | awk '{print $2 % $1; }'
}


## @fn get_local_bias_numer()
## @brief Ermittle eine lokale einzigartige Zahl, die als dauerhaft unveränderlich angenommen werden kann.
## @returns Eine (initial zufällig ermittelte) Zahl zwischen 0 und 10^8-1, die unveränderlich zu diesem AP gehört. 
## @details Für ein paar gleichrangige Sortierungen (z.B. verwendete
##   UGW-Gegenstellen) benötigen wir ein lokales Salz, um strukturelle
##   Bevorzugungen zu vermeiden.
get_local_bias_number() {
	trap 'error_trap get_local_bias_number "$*"' EXIT
	local bias
	bias=$(uci_get on-core.settings.local_bias_number)
	# der Bias-Wert ist schon vorhanden - wir liefern ihn aus
	if [ -z "$bias" ]; then
		# wir müssen einen Bias-Wert erzeugen: beliebige gehashte Inhalte ergeben eine akzeptable Zufallszahl
		bias=$(get_random 100000000)
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
	local result
	# shellcheck disable=SC1091,SC2034
	result=$(set +eu; . /lib/functions/service.sh; SERVICE_PID_FILE="$pid_file"; service_check "$executable" && echo "ok"; set -eu)
	[ -n "$result" ] && return 0
	trap "" EXIT && return 1
}


## @fn get_memory_size()
## @brief Ermittle die Größe des Arbeitsspeichers in Megabyte.
## @returns Der Rückgabewert (in Megabyte) ist etwas kleiner als der physische Arbeitsspeicher (z.B. 126 statt 128 MB).
get_memory_size() {
	local memsize_kb
	memsize_kb=$(grep "^MemTotal:" /proc/meminfo | sed 's/[^0-9]//g')
	echo $((memsize_kb / 1024))
}


# Liefere alle Dateien in einem Verzeichnis zurück, die entsprechend der "run-parts"-Funktionalität
# beachtet werden sollten.
_get_parts_dir_files() {
	local parts_dir="$1"
	local fname
	# Abbruch, falls es das Verzeichnis nicht gibt
	[ -e "$parts_dir" ] || return 0
	# ignoriere Dateinamen mit ungueltigen Zeichen (siehe 'man run-parts')
	find "$parts_dir" -maxdepth 1 | grep '/[a-zA-Z0-9_-]\+$' | sort | while read -r fname; do
		# ignoriere verwaiste symlinks
		[ -f "$fname" ] || continue
		# ignoriere Dateien ohne Ausführungsrechte
		[ -x "$fname" ] || continue
		echo "$fname"
	done
}


## @fn run_parts()
## @brief Führe alle Skripte aus, die in einem bestimmten Verzeichnis liegen und gewissen Konventionen genügen.
## @param rundir Verzeichnis, das die auszuführenden Skripte enthält
## @param weitere Paramter (falls erforderlich)
## @details Die Namenskonventionen und das Verhalten entspricht dem verbreiteten 'run-parts'-Werkzeug.
##     Die Dateien müssen ausführbar sein.
run_parts() {
	trap 'error_trap run_parts "$*"' EXIT
	local rundir="$1"
	shift
	local fname
	_get_parts_dir_files "$rundir" | while read -r fname; do
		msg_debug "on-run-parts: executing $fname"
		# ignoriere Fehler bei der Ausfuehrung
		"$fname" "$@" || true
	done
}


## @fn schedule_parts()
## @brief Plant die Ausführung aller Skripte, die in einem bestimmten Verzeichnis liegen und gewissen Konventionen genügen.
## @param rundir Verzeichnis, das die auszuführenden Skripte enthält
## @param suffix optionaler Suffix wird ungefiltert an jeden auszufühenden Dateinamen gehängt (z.B. '2>&1 | logger -t cron-error')
## @details Die Namenskonventionen und das Verhalten entspricht dem verbreiteten 'run-parts'-Werkzeug.
##     Die Dateien müssen ausführbar sein.
schedule_parts() {
	trap 'error_trap schedule_parts "$*"' EXIT
	local rundir="$1"
	local suffix="${2:-}"
	_get_parts_dir_files "$rundir" | while read -r fname; do
		if [ -n "$suffix" ]; then
			echo "$fname $suffix"
		else
			echo "$fname"
		fi | schedule_task
	done
}


## @fn run_scheduled_tasks()
## @brief Führe die zwischenzeitlich für die spätere Ausführung vorgemerkten Aufgaben aus.
## @details Unabhängig vom Ausführungsergebnis wird das Skript anschließend gelöscht.
run_scheduled_tasks() {
	trap 'error_trap run_scheduled_tasks "$*"' EXIT
	local fname
	local temp_fname
	local running_tasks
	[ -d "$SCHEDULING_DIR" ] || return 0
	# keine Ausführung, falls noch mindestens ein alter Task aktiv ist
	running_tasks=$(find "$SCHEDULING_DIR" -type f -name "*.running" | while read -r fname; do
		# veraltete Dateien werden geloescht und ignoriert
		# wir müssen uns an dem langsamsten Cron-Job orientieren:
		#	- MTU-Test für UGWs: ca. 5 Minuten
		#	- update_olsr_services: mehr als 5 Minuten
		is_file_timestamp_older_minutes "$fname" 30 && rm -f "$fname" && continue
		# nicht-veraltete Dateien fuehren zum Abbruch der Funktion
		msg_info "Skipping 'run_scheduled_task' due to an ongoing operation: $(tail -1 "$fname")"
		echo "$fname"
	done)
	[ -n "$running_tasks" ] && return 0
	# die ältesten Dateien zuerst ausführen
	find "$SCHEDULING_DIR" -type f | grep -v '\.running$' | xargs -r ls -tr | while read -r fname; do
		temp_fname="${fname}.running"
		# zuerst schnell wegbewegen, damit wir keine Ereignisse verpassen
		# Im Fehlerfall (eine race condition) einfach beim naechsten Eintrag weitermachen.
		mv "$fname" "$temp_fname" 2>/dev/null || continue
		{ /bin/sh "$temp_fname" | logger -t "on-scheduled"; } 2>&1 | logger -t "on-scheduled-error"
		rm -f "$temp_fname"
	done
}


## @fn schedule_task()
## @brief Erzeuge ein Start-Skript für die baldige Ausführung einer Aktion.
## @details Diese Methode sollte für Aufgaben verwendet werden, die nicht unmittelbar ausgeführt
##   werden müssen und im Zweifelsfall nicht parallel ablaufen sollen (ressourcenschonend).
schedule_task() {
	trap 'error_trap schedule_task "$*"' EXIT
	local script_content
	local unique_key
	script_content=$(cat -)
	# wir sorgen fuer die Wiederverwendung des Dateinamens, um doppelte Ausführungen zu verhindern
	unique_key=$(echo "$script_content" | md5sum | awk '{ print $1 }')
	local target_file="$SCHEDULING_DIR/$unique_key"
	# das Skript existiert? Nichts zu tun ...
	[ -e "$target_file" ] && return 0
	mkdir -p "$SCHEDULING_DIR"
	echo "$script_content" >"$target_file"
}


## @fn schedule_parts()
## @brief Merke alle Skripte in einem Verzeichnis für die spätere Ausführung via 'run_scheduled_tasks' vor.
## @details Die Namenskonventionen und das Verhalten entspricht dem verbreiteten 'run-parts'-Werkzeug.
##     Die Dateien müssen ausführbar sein.
schedule_parts() {
	trap 'error_trap schedule_parts "$*"' EXIT
	local schedule_dir="$1"
	local fname
	_get_parts_dir_files "$schedule_dir" | while read -r fname; do
		msg_debug "on-schedule-parts: scheduling $fname"
		# ignoriere Fehler bei der Ausfuehrung
		echo "$fname" | schedule_task
	done
}


## @fn read_data_bytes()
## @brief Bytes von einem Blockdevice lesen
## @param source das Quell-Blockdevice (oder die Datei)
## @param size die Anzahl der zu uebertragenden Bytes
## @param transfer_blocksize die Blockgroesse bei der Uebertragung (Standard: 65536)
## @details Die verwendete Uebertragung in grossen Bloecken ist wesentlich schneller als das byteweise EinlesenaKopie.sh_backup
##   Der abschliessende unvollstaendige Block wird byteweise eingelesen.
read_data_bytes() {
	local size="$1"
	local transfer_blocksize="${2:-65536}"
	# "conv=sync" ist fuer die "yes"-Quelle erforderlich - sonst fehlt gelegentlich der letzte Block.
	# Es scheint sich dazu bei um eine race-condition zu handeln.
	dd "bs=$transfer_blocksize" "count=$((size / transfer_blocksize))" conv=sync 2>/dev/null
	[ "$((size % transfer_blocksize))" -ne 0 ] && dd bs=1 "count=$((size % transfer_blocksize))" 2>/dev/null
	true
}


## @fn get_flash_backup()
## @brief Erzeuge einen rohen Dump des Flash-Speichers. Dieser ermöglicht den Austausch des Flash-Speichers.
## @param include_private Kopiere neben den nur-Lese-Bereichen auch die aktuelle Konfiguration inkl. eventueller privater Daten.
## @details Alle mtd-Partition bis auf den Kernel und die Firmware werden einzeln kopiert und dann komprimiert.
##   Beispiel-Layout einer Ubiquiti Nanostation:
##     dev:    size   erasesize  name
##     mtd0: 00040000 00010000 "u-boot"
##     mtd1: 00010000 00010000 "u-boot-env"
##     mtd2: 00760000 00010000 "firmware"
##     mtd3: 00102625 00010000 "kernel"
##     mtd4: 0065d9db 00010000 "rootfs"
##     mtd5: 00230000 00010000 "rootfs_data"
##     mtd6: 00040000 00010000 "cfg"
##     mtd7: 00010000 00010000 "EEPROM"
##   Dabei ignorieren wir bei Bedarf "rootfs_data" (beschreibbarer Bereich der Firmware). 
get_flash_backup() {
	trap 'error_trap get_flash_backup "$*"' EXIT
	local include_private="${1:-}"
	local name
	local size
	local blocksize
	local label
	# shellcheck disable=SC2034
	grep '^mtd[0-9]\+:' /proc/mtd | while read -r name size blocksize label; do
		# abschliessenden Doppelpunkt entfernen
		name="${name%:}"
		# hexadezimal-Zahl umrechnen
		size=$(echo | awk "{print 0x$size }")
		# Anfuehrungszeichen entfernen
		label=$(echo "$label" | cut -f 2 -d '"')
		# Firmware-Partitionen ueberspringen
		if [ "$label" = "rootfs" ]; then
			local rootfs_device="/dev/$name"
			local rootfs_full_size="$size"
		elif [ "$label" = "rootfs_data" ]; then
			# schreibe das komplette rootfs _ohne_ das aktuelle rootfs_data
			echo >&2 "Read: root-RO $((rootfs_full_size - size))"
			# Transfer blockweise vornehmen - byteweise dauert es zu lang
			read_data_bytes "($((rootfs_full_size - size)))" <"$rootfs_device"
			if [ -z "$include_private" ]; then
				echo >&2 "Read: root-zero ($size)"
				# erzeuge 0xFF
				# siehe http://stackoverflow.com/a/10905109
				tr '\0' '\377' </dev/zero | read_data_bytes "$size"
			else
				echo >&2 "Read: root-RW ($size)"
				# auch das private rootfs-Dateisystem (inkl. Schluessel, Passworte, usw.) auslesen
				read_data_bytes "$size" <"/dev/$name"
			fi
		elif [ "$label" = "firmware" ]; then
			echo >&2 "Skip: $label ($size)"
			# ignoriere die meta-Partition (kernel + rootfs)
			true
		else
			echo >&2 "Read: $label ($size)"
			cat "/dev/$name"
		fi
	done
}


## @fn has_flash_or_filesystem_error_indicators()
## @brief Prüfe ob typische Indikatoren (vor allem im Kernel-Log) vorliegen, die auf einen Flash-Defekt hinweisen.
has_flash_or_filesystem_error_indicators() {
	trap 'error_trap get_flash_backup "$*"' EXIT
	dmesg | grep -q "jffs2.*CRC" && return 0
	dmesg | grep -q "SQUASHFS error" && return 0
	# keine Hinweise gefunden -> wir liefern "nein"
	trap "" EXIT && return 1
}

# Ende der Doku-Gruppe
## @}
