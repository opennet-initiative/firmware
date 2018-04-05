## @defgroup openvpn OpenVPN (allgemein)
## @brief Vorbereitung, Konfiguration und Prüfung von VPN-Verbindungen (z.B. für Nutzertunnel oder UGW). 
# Beginn der openvpn-Doku-Gruppe
## @{


OPENVPN_CONFIG_BASEDIR=/var/etc/openvpn


## @fn enable_openvpn_service()
## @brief Erzeuge eine funktionierende openvpn-Konfiguration (Datei + UCI).
## @param service_name Name eines Dienstes
## @details Die Konfigurationsdatei wird erzeugt und eine openvpn-uci-Konfiguration wird angelegt.
##   Falls zu diesem openvpn-Dienst kein Zertifikat oder kein Schlüssel gefunden wird, dann passiert nichts.
enable_openvpn_service() {
	trap 'error_trap enable_openvpn_service "$*"' EXIT
	local service_name="$1"
	local config_file="$OPENVPN_CONFIG_BASEDIR/${service_name}.conf"
	if ! openvpn_service_has_certificate_and_key "$service_name"; then
		msg_info "Refuse to enable openvpn server ('$service_name'): missing key or certificate"
		trap "" EXIT && return 1
	fi
	local uci_prefix="openvpn.$service_name"
	# zukuenftige config-Datei referenzieren
	update_vpn_config "$service_name" "$config_file"
	# zuvor ankuendigen, dass zukuenftig diese uci-Konfiguration an dem Dienst haengt
	service_add_uci_dependency "$service_name" "$uci_prefix"
	# lege die uci-Konfiguration an und aktiviere sie
	uci set "${uci_prefix}=openvpn"
	uci set "${uci_prefix}.enabled=1"
	uci set "${uci_prefix}.config=$config_file"
	apply_changes openvpn
}


## @fn update_vpn_config()
## @brief Schreibe eine openvpn-Konfigurationsdatei.
## @param service_name Name eines Dienstes
update_vpn_config() {
	trap 'error_trap update_vpn_config "$*"' EXIT
	local service_name="$1"
	local config_file="$2"
	service_add_file_dependency "$service_name" "$config_file"
	# Konfigurationsdatei neu schreiben
	mkdir -p "$(dirname "$config_file")"
	get_openvpn_config "$service_name" >"$config_file"
}


## @fn disable_openvpn_service()
## @brief Löschung einer openvpn-Verbindung
## @param service_name Name eines Dienstes
## @details Die UCI-Konfiguration, sowie alle anderen mit der Verbindung verbundenen Elemente werden entfernt.
##   Die openvpn-Verbindung bleibt bestehen, bis zum nächsten Aufruf von 'apply_changes openvpn'.
disable_openvpn_service() {
	trap 'error_trap disable_openvpn_service "$*"' EXIT
	local service_name="$1"
	# Abbruch, falls es keine openvpn-Instanz gibt
	[ -z "$(uci_get "openvpn.$service_name")" ] && return 0
	# openvpn wird automatisch neugestartet
	cleanup_service_dependencies "$service_name"
	# nach einem reboot sind eventuell die dependencies verlorengegangen - also loeschen wir manuell
	uci_delete "openvpn.$service_name"
}


## @fn get_openvpn_service_state()
## @brief Prüfe ob eine openvpn-Verbindung besteht bzw. im Aufbau ist.
## @param service_name Name eines Dienstes
## @details Die Prüfung wird anhand der PID-Datei und der Gültigkeit der enthaltenen PID vorgenommen.
## @returns "active", "connecting" oder einen leeren String (unbekannt, bzw. keine Verbindung).
get_openvpn_service_state() {
	trap 'error_trap get_openvpn_service_state "$*"' EXIT
	local service_name="$1"
	local pid_file
	# existiert ein VPN-Eintrag?
	[ -z "$(uci_get "openvpn.$service_name")" ] && return
	# gibt es einen Verweis auf eine passende PID-Datei?
	pid_file=$(get_openvpn_service_pid_file "$service_name")
	if check_pid_file "$pid_file" "openvpn"; then
		# Die "openvpn_established_indicator_file"-Variable wird vom up/down-Skript erzeugt.
		# Die Variable verweist ebenfalls auf eine Datei mit der PID. Dies erlaubt die Unterscheidung
		# einer Verbindung im Aufbau (bzw. in der Phase einer wiederholten Ablehnung) von einer
		# beiderseits akzeptierten Datenverbindung. Dies ist insbesondere fuer die mesh-VPN-Verbindungen
		# sinnvoll, da hier mehr Toleranz beim Verbindungsaufbau sinnvoll ist.
		if check_pid_file "$(get_service_value "$service_name" "openvpn_established_indicator_file")" "openvpn"; then
			echo -n "active"
		else
			echo -n "connecting"
		fi
	else
		true
	fi
}


## @fn _change_openvpn_config_setting()
## @brief Ändere eine Einstellung in einer openvpn-Konfigurationsdatei.
## @param config_file Name der Konfigurationsdatei.
## @param config_key Name der openvpn-Einstellung.
## @param config_value Neuer Inhalt der Einstellung - die Einstellung wird gelöscht, falls dieser Parameter fehlt oder leer ist.
## @attention OpenVPN-Optionen ohne Parameter (z.B. --mtu-test) können nicht mittels dieser Funktion gesetzt werden.
_change_openvpn_config_setting() {
	local config_file="$1"
	local config_key="$2"
	local config_value="${3:-}"
	sed -i "/^$config_key[\t ]/d" "$config_file"
	[ -n "$config_value" ] && echo "$config_key $config_value" >>"$config_file"
	return 0
}


## @fn get_openvpn_config()
## @brief liefere openvpn-Konfiguration eines Dienstes zurück
## @param service_name Name eines Dienstes
get_openvpn_config() {
	trap 'error_trap get_openvpn_config "$*"' EXIT
	local service_name="$1"
	local remote
	local port
	local protocol
	local template_file
	local pid_file
	local proxy_service_type
	local relayed_service
	remote=$(get_service_value "$service_name" "host")
	port=$(get_service_value "$service_name" "port")
	# Falls es sich um einen relay-Dienst handelt, koennen wir uns leider nicht mit uns selbst verbinden,
	# da die firewall-redirect-Regeln keine "device"-Quelle kennen (anstelle des ueblichen "on_mesh").
	# Also ermitteln wir den lokal bekannten proxy-Dienst und verwenden dessen Daten, sofern on-usergw installiert ist.
	if [ "$remote" = "$(get_main_ip)" ] && [ -n "${RELAYABLE_SERVICE_PREFIX:-}" ]; then
		proxy_service_type="$RELAYABLE_SERVICE_PREFIX$(get_service_value "$service_name" "service")"
		relayed_service=$(get_services "$proxy_service_type" | filter_services_by_value "local_relay_port" "$port")
		if [ -n "$relayed_service" ]; then
			# Hostname und Port ersetzen
			remote=$(get_service_value "$relayed_service" "host")
			port=$(get_service_value "$relayed_service" "port")
		else
			msg_info "Failed to use locally relayed service for openvpn - trying to continue, anyway."
		fi
	fi
	protocol=$(get_service_value "$service_name" "protocol")
	template_file=$(get_openvpn_service_template_filename "$service_name")
	pid_file=$(get_openvpn_service_pid_file "$service_name")
	# schreibe die Konfigurationsdatei
	echo "# automatically generated by $0"
	echo "remote $remote $port $protocol"
	echo "writepid $pid_file"
	cat "$template_file"
	# sicherstellen, dass die Konfigurationsdatei mit einem Zeilenumbruch endet (fuer "echo >> ...")
	echo
}


## @fn verify_vpn_connection()
## @brief Prüfe einen VPN-Verbindungsaufbau
## @param service_name Name eines Dienstes
## @param key [optional] Schluesseldatei: z.B. $VPN_DIR/on_aps.key
## @param cert [optional] Zertifikatsdatei: z.B. $VPN_DIR/on_aps.crt
## @returns Exitcode=0 falls die Verbindung aufgebaut werden konnte
verify_vpn_connection() {
	trap 'error_trap verify_vpn_connection "$*"' EXIT
	local service_name="$1"
	local key_file="${2:-}"
	local cert_file="${3:-}"
	local config_file
	local log_file
	local file_opts
	config_file=$(mktemp -t "VERIFY-${service_name}-XXXXXXX")
	log_file=$(get_service_log_filename "$service_name" "openvpn" "verify")
	# wir benoetigen die template-Datei fuer das Erzeugen der Basis-Konfiguration
	msg_debug "start vpn test of $service_name"
	# erstelle die config-Datei
	(
		# filtere Einstellungen heraus, die wir ueberschreiben wollen
		# nie die echte PID-Datei ueberschreiben (falls ein Prozess laeuft)
		get_openvpn_config "$service_name"

		# some openvpn options:
		#   ifconfig-noexec: we do not want to configure a device (and mess up routing tables)
		#   route-noexec: keinerlei Routen hinzufuegen
		echo "ifconfig-noexec"
		echo "route-noexec"

		# some timing options:
		#   inactive: close connection after 15s without traffic
		#   ping-exit: close connection after 15s without a ping from the other side (which is probably disabled)
		echo "inactive 15 1000000"
		echo "ping-exit 15"

		# other options:
		#   verb: verbose level 3 is required for the TLS messages
		#   nice: testing is not too important
		#   resolv-retry: fuer ipv4/ipv6-Tests sollten wir mehrere Versuche zulassen
		echo "verb 4"
		echo "nice 3"
		echo "resolv-retry 3"

		# prevent a real connection (otherwise we may break our current vpn tunnel):
		#   tls-exit: stop immediately after tls handshake failure
		#   ns-cert-type: enforce a connection against a server certificate (instead of peer-to-peer)
		echo "tls-exit"
		echo "ns-cert-type server"

	) >"$config_file"

	# kein Netzwerkinterface erzeugen
	_change_openvpn_config_setting "$config_file" "dev" "null"
	# keine PID-Datei anlegen
	_change_openvpn_config_setting "$config_file" "writepid" ""
	# keine Netzwerkkonfiguration via up/down
	_change_openvpn_config_setting "$config_file" "up" ""
	_change_openvpn_config_setting "$config_file" "down" ""
	# TLS-Pruefung immer fehlschlagen lassen
	_change_openvpn_config_setting "$config_file" "tls-verify" "/bin/false"
	# Log-Datei anlegen
	_change_openvpn_config_setting "$config_file" "log" "$log_file"

	# nur fuer tcp-Verbindungen (ipv4/ipv6)
	#   connect-retry: Sekunden Wartezeit zwischen Versuchen
	#   connect-timeout: Dauer eines Versuchs
	#   connect-retry-max: Anzahl moeglicher Wiederholungen
	if grep -q "^remote.*tcp" "$config_file"; then
		{
			echo "connect-retry 1"
			echo "connect-timeout 15"
			echo "connect-retry-max 1"
		} >>"$config_file"
	fi

	# Schluessel und Zertifikate bei Bedarf austauschen
	[ -n "$key_file" ] && \
		_change_openvpn_config_setting "$config_file" "key" "$key_file"
	[ -n "$cert_file" ] && \
		_change_openvpn_config_setting "$config_file" "cert" "$cert_file"

	# Aufbau der VPN-Verbindung bis zum Timeout oder bis zum Verbindungsabbruch via "tls-exit" (/bin/false)
	openvpn --config "$config_file" || true
	# read the additional options from the config file (for debug purposes)
	file_opts=$(grep -v "^$" "$config_file" | grep -v "^#" | sed 's/^/--/' | tr '\n' ' ')
	rm -f "$config_file"
	if [ -e "$log_file" ]; then
		grep -q "Initial packet" "$log_file" && return 0
		msg_debug "openvpn test failed: openvpn $file_opts"
	else
		# Die Log-Datei sollte nur dann fehlen, wenn die openvpn-Konfiguration defekt ist
		# und somit den Start von openvpn verhindert.
		msg_error "openvpn test failed unexpectedly: configuration error?"
	fi
	trap "" EXIT && return 1
}


## @fn openvpn_service_has_certificate_and_key()
## @brief Prüfe ob das Zertifikat eines openvpn-basierten Diensts existiert.
## @returns exitcode=0 falls das Zertifikat existiert
## @details Falls der Ort der Zertifikatsdatei nicht zweifelsfrei ermittelt
##   werden kann, dann liefert die Funktion "wahr" zurück.
openvpn_service_has_certificate_and_key() {
	local service_name="$1"
	local cert_file
	local key_file
	local config_template
	config_template=$(get_service_value "$service_name" "template")
	# im Zweifelsfall (kein Template gefunden) liefern wir "wahr"
	[ -z "$config_template" ] && return 0
	# Verweis auf lokale config-Datei (keine uci-basierte Konfiguration)
	if [ -e "$config_template" ]; then
		cert_file=$(_get_file_dict_value "cert" "$config_template")
		key_file=$(_get_file_dict_value "key" "$config_template")
	else
		# im Zweifelsfall: liefere "wahr"
		return 0
	fi
	# das Zertifikat scheint irgendwie anders konfiguriert zu sein - im Zeifelsfall: OK
	if [ -z "$cert_file" ] || [ -z "$key_file" ]; then
		return 0
	elif [ -e "$cert_file" ] && [ -e "$key_file" ]; then
		# alle relevanten Dateien existieren
		return 0
	else
		trap "" EXIT && return 1
	fi
}


## @fn has_openvpn_credentials_by_template()
## @brief Prüft, ob der Nutzer bereits einen Schlüssel und ein Zertifikat angelegt hat.
## @param template_file Name einer openvpn-Konfigurationsdatei (oder einer Vorlage). Aus dieser Datei werden "cert"- und "key"-Werte entnommen.
## @returns Liefert "wahr", falls Schlüssel und Zertifikat vorhanden sind oder falls in irgendeiner Form Unklarheit besteht.
has_openvpn_credentials_by_template() {
	trap 'error_trap has_openvpn_credentials_by_template "$*"' EXIT
	local template_file="$1"
	local cert_file
	local key_file
	local base_dir
	cert_file=$(_get_file_dict_value "cert" "$template_file")
	key_file=$(_get_file_dict_value "key" "$template_file")
	# Pruefe, ob eine "cd"-Direktive enthalten ist - vervollständige damit relative Pfade
	base_dir=$(_get_file_dict_value "cd" "$template_file")
	[ -n "$base_dir" ] && [ "${cert_file:0:1}" != "/" ] && cert_file="$base_dir/$cert_file"
	[ -n "$base_dir" ] && [ "${key_file:0:1}" != "/" ] && key_file="$base_dir/$key_file"
	# im Zweifel: liefere "wahr"
	if [ -z "$key_file" ] || [ -z "$cert_file" ]; then
		return 0
	elif [ -e "$key_file" ] && [ -e "$cert_file" ]; then
		# beide Dateien existieren
		return 0
	else
		trap "" EXIT && return 1
	fi
}


## @fn log_openvpn_events_and_disconnect_if_requested()
## @brief Allgemeines Ereignisbehandlung fuer openvpn-Verbindungen: Logging und eventuell Dienst-Bereinigung (nur für "down").
## @details Alle Informationen (bis auf das Log-Ziel) werden aus den Umgebungsvariablen gezogen, die openvpn in
##   seinen Ereignisskripten setzt.
log_openvpn_events_and_disconnect_if_requested() {
	local log_target="$1"
	# die config-Datei enthaelt den Dienst-Namen
	local service_name
	local pid_file
	local established_indicator_file
	local service_type
	local service_host
	local now
	local same_host_service
	# die folgenden Variablen stammen aus der OpenVPN-Umgebung
	config=${config:-}
	script_type=${script_type:-}
	remote_1=${remote_1:-}
	remote_port_1=${remote_port_1:-}
	daemon_start_time=${daemon_start_time:-}
	# es geht los ...
	service_name=$(basename "${config%.conf}")
	pid_file=$(get_openvpn_service_pid_file "$service_name")
	established_indicator_file=$(get_service_value "$service_name" "openvpn_established_indicator_file")
	if [ -z "$established_indicator_file" ] && [ -n "$pid_file" ]; then
		established_indicator_file="${pid_file}.established"
		set_service_value "$service_name" "openvpn_established_indicator_file" "$established_indicator_file"
	fi
	case "$script_type" in
		up)
			append_to_custom_log "$log_target" "up" "Connecting to ${remote_1}:${remote_port_1}"
			[ -n "$pid_file" ] && cat "$pid_file" >"$established_indicator_file"
			true
			;;
		down)
			# der openwrt-Build von openvpn setzt wohl leider nicht die "time_duration"-Umgebungsvariable
			[ -z "${time_duration:-}" ] && time_duration=$(($(date +%s) - daemon_start_time))
			# Verbindungsverlust durch fehlende openvpn-Pings?
			if [ "${signal:-}" = "ping-restart" ]; then
				service_type=$(get_service_value "$service_name" "service")
				service_host=$(get_service_value "$service_name" "host")
				now=$(get_uptime_minutes)
				append_to_custom_log "$log_target" "down" \
					"Lost connection with ${remote_1}:${remote_port_1} after ${time_duration}s"
				# alle Verbindungen derselben Art zu diesem Host als unklar definieren
				for same_host_service in $(get_services "$service_type" \
						| filter_services_by_value "host" "$service_host"); do
					set_service_value "$same_host_service" "status" ""
					set_service_value "$same_host_service" "status_timestamp" "$now"
				done
				disable_openvpn_service "$service_name"
				[ -n "$pid_file" ] && rm -f "$pid_file"
				[ -n "$established_indicator_file" ] && rm -f "$established_indicator_file"
				true
			else
				append_to_custom_log "$log_target" "down" \
					"Closing connection with ${remote_1}:${remote_port_1} after ${time_duration}s"
			fi
			;;
		*)
			append_to_custom_log "$log_target" "other" "${remote_1}:${remote_port_1}"
			;;
	esac
}


## @fn get_openvpn_service_pid_file()
## @param Name eines Diensts
## @brief PID-Datei für diesen Dienst ausgeben.
get_openvpn_service_pid_file() {
	local service_name="$1"
	echo "/var/run/${service_name}.pid"
}


## @fn get_openvpn_service_template_filename()
## @param Name des Diensts
## @brief Dateiname der Konfigurationsvorlage dieses Diensts ausgeben.
get_openvpn_service_template_filename() {
	trap 'error_trap get_openvpn_service_template_filename "$*"' EXIT
	local service_name="$1"
	local service_type
	service_type=$(get_service_value "$service_name" "service")
	# Diese Stelle ist hier eigentlich falsch, da sie Kenntnisse und Variablen
	# vorraussetzt, die nicht in "on-core" definiert sind.
	# Aufgrund der Wiederverwendung der generischen
	# "run_cyclic_service_tests"-Funktion ist eine Separierung dieser Auswahl
	# jedoch leider nur mit großem Aufwand möglich.
	if [ "$service_type" = "gw" ]; then
		echo "$MIG_OPENVPN_CONFIG_TEMPLATE_FILE"
	elif [ "$service_type" = "mesh" ]; then
		echo "$MESH_OPENVPN_CONFIG_TEMPLATE_FILE"
	else
		msg_error "unknown service type for openvpn config preparation: $service_type"
		trap "" EXIT && return 1
	fi
}


## @fn openvpn_get_mtu()
## @brief Ermittle die MTU auf dem Weg zum Anbieter des Diensts.
## @details The output can be easily parsed via 'cut'. Even the full status output of openvpn is safe for parsing since potential tabulator characters are removed.
## @returns One line consisting of five fields separated by tab characters is returned (tried_to_remote real_to_remote tried_from_remote real_from_remote full_status_output). Failed tests are indicated by an empty result.
openvpn_get_mtu() {
	trap 'error_trap openvpn_get_mtu "$*"' EXIT
	local service_name="$1"
	local config_file
	local pid_file
	local log_file
	local host
	config_file=$(mktemp -t "MTU-${service_name}-XXXXXXX")
	pid_file="$(mktemp)"
	log_file="$(get_service_log_filename "$service_name" "openvpn" "mtu")"
	host=$(get_service_value "$service_name" "host")

	(
		get_openvpn_config "$service_name"
		# kein Netzwerk konfigurieren
		echo "ifconfig-noexec"
		echo "route-noexec"
	) >"$config_file"

	# kein Netzwerkinterface, keine pid-Datei
	_change_openvpn_config_setting "$config_file" "dev" "null"
	_change_openvpn_config_setting "$config_file" "writepid" "$pid_file"

	# Log-Datei anlegen
	_change_openvpn_config_setting "$config_file" "log" "$log_file"
	_change_openvpn_config_setting "$config_file" "verb" "4"

	# keine Skripte
	_change_openvpn_config_setting "$config_file" "up" ""
	_change_openvpn_config_setting "$config_file" "down" ""

	openvpn --mtu-test --config "$config_file" 2>&1 &
	# warte auf den Startvorgang
	sleep 3
	local wait_loops=40
	local pid
	pid=$(cat "$pid_file" 2>/dev/null || true)
	local mtu_out
	local mtu_out_filtered
	while [ "$wait_loops" -gt 0 ]; do
		# keine Fehlermeldungen (-s) falls die Log-Datei noch nicht existiert
		mtu_out=$(grep -s "MTU test completed" "$log_file" || true)
		# for example
		# Thu Jul  3 22:23:01 2014 NOTE: Empirical MTU test completed [Tried,Actual] local->remote=[1573,1573] remote->local=[1573,1573]
		if [ -n "$mtu_out" ]; then
			# Ausgabe der vier Zahlen getrennt durch Tabulatoren
			mtu_out_filtered="$(echo "$mtu_out" | tr '[' ',' | tr ']' ',')"
			# Leider koennen wir nicht alle Felder auf einmal ausgeben (tab-getrennt),
			# da das busybox-cut nicht den --output-delimiter unterstützt.
			echo "$mtu_out_filtered" | cut -d , -f 5 | tr '\n' '\t'
			echo "$mtu_out_filtered" | cut -d , -f 6 | tr '\n' '\t'
			echo "$mtu_out_filtered" | cut -d , -f 8 | tr '\n' '\t'
			echo "$mtu_out_filtered" | cut -d , -f 9 | tr '\n' '\t'
			# wir ersetzen alle eventuell vorhandenen Tabulatoren in der Statusausgabe - zur Vereinfachung des Parsers
			echo -n "$mtu_out" | tr '\t' ' '
			break
		elif [ -z "$pid" ] || [ ! -d "/proc/$pid" ]; then
			msg_info "Failed to verify MTU resctrictions for '$host'"
			break
		fi
		sleep 10
		wait_loops=$((wait_loops - 1))
	done
	# sicherheitshalber brechen wir den Prozess ab und loeschen alle Dateien
	kill "$pid" >/dev/null 2>&1 || true
	rm -f "$config_file" "$pid_file"
	# ist der Zaehler abgelaufen?
	[ "$wait_loops" -eq 0 ] && msg_info "Timeout for openvpn_get_mtu '$host' - aborting."
	return 0
}


## @fn cleanup_stale_openvpn_services()
## @brief Beräumung liegengebliebener openvpn-Konfigurationen, sowie Deaktivierung funktionsunfähiger Verbindungen.
## @details Verwaiste openvpn-Konfigurationen können aus zwei Grunden auftreten:
##   1) nach einem reboot wurde nicht die zuletzt aktive openvpn-Verbindung ausgewählt - somit
##      bleibt der vorher aktive uci-Konfigurationseintrag erhalten
##   2) ein VPN-Verbindungsaufbau scheitert und hinterlässt einen uci-Eintrag, eine PID-Datei,
##      jedoch keinen laufenden Prozess
##  Achtung: falls eine Verbindung sich gerade im Aufbau befindet, wird ihre Konfiguration
##           ebenfalls entfernt. Diese Funktion sollte also nur in ausgewählten Situation
##           aufgerufen werden (nach einem Reboot und nach einem Verbindungsabbruch).
cleanup_stale_openvpn_services() {
	trap 'error_trap cleanup_stale_openvpn_services "$*"' EXIT
	local service_name
	local config_file
	local pid_file
	local uci_prefix
	for uci_prefix in $(find_all_uci_sections "openvpn" "openvpn"); do
		config_file=$(uci_get "${uci_prefix}.config")
		# Keine config-Datei? Keine von uns verwaltete Konfiguration ...
		[ -z "$config_file" ] && continue
		service_name="${uci_prefix#openvpn.}"
		# Es scheint sich um eine von uns verwaltete Verbindung zu handeln.
		pid_file=$(get_openvpn_service_pid_file "$service_name")
		# Falls die config-Datei oder die pid-Datei fehlt, dann ist es ein reboot-Fragment. Wir löschen die Überreste.
		if [ ! -e "$config_file" ] || [ ! -e "$pid_file" ]; then
			msg_info "Removing a reboot-fragment of a previously used openvpn connection: $service_name"
			disable_openvpn_service "$service_name"
		elif check_pid_file "$pid_file" "openvpn"; then
			# Prozess läuft - alles gut
			true
		else
			# Falls die PID-Datei existiert, jedoch veraltet ist (kein dazugehöriger Prozess läuft), dann
			# schlug der Verbindungsaufbau fehlt (siehe "tls-exit" und "single-session").
			# Wir markieren die Verbindung als kaputt.
			msg_info "Marking a possibly interrupted openvpn connection as broken: $service_name"
			set_service_value "$service_name" "status" "n"
			disable_openvpn_service "$service_name"
		fi
	done
	apply_changes openvpn
}

# Ende der openvpn-Doku-Gruppe
## @}
