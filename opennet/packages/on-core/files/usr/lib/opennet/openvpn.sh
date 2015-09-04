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
	trap "error_trap enable_openvpn_service '$*'" $GUARD_TRAPS
	local service_name="$1"
	if ! openvpn_service_has_certificate_and_key "$service_name"; then
		msg_info "Refuse to enable openvpn server ('$service_name'): missing key or certificate"
		trap "" $GUARD_TRAPS && return 1
	fi
	# ermittle die openvpn-config-Vorlagedatei
	prepare_openvpn_service "$service_name"
	local uci_prefix="openvpn.$service_name"
	local config_file
	config_file=$(get_service_value "$service_name" "config_file")
	# zukuenftige config-Datei referenzieren
	update_vpn_config "$service_name"
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
	trap "error_trap update_vpn_config '$*'" $GUARD_TRAPS
	local service_name="$1"
	local config_file
	config_file=$(get_service_value "$service_name" "config_file")
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
	trap "error_trap disable_openvpn_service '$*'" $GUARD_TRAPS
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
	trap "error_trap get_openvpn_service_state '$*'" $GUARD_TRAPS
	local service_name="$1"
	# existiert ein VPN-Eintrag?
	[ -z "$(uci_get "openvpn.$service_name")" ] && return
	# gibt es einen Verweis auf eine passende PID-Datei?
	if check_pid_file "$(get_service_value "$service_name" "pid_file")" "openvpn"; then
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
	trap "error_trap get_openvpn_config '$*'" $GUARD_TRAPS
	local service_name="$1"
	local remote
	local port
	local protocol
	local template_file
	local pid_file
	remote=$(get_service_value "$service_name" "host")
	port=$(get_service_value "$service_name" "port")
	protocol=$(get_service_value "$service_name" "protocol")
	[ "$protocol" = "tcp" ] && protocol=tcp-client
	template_file=$(get_service_value "$service_name" "template_file")
	pid_file=$(get_service_value "$service_name" "pid_file")
	# schreibe die Konfigurationsdatei
	echo "# automatically generated by $0"
	echo "remote $remote $port"
	echo "proto $protocol"
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
	trap "error_trap verify_vpn_connection '$*'" $GUARD_TRAPS
	local service_name="$1"
	local key_file="${2:-}"
	local cert_file="${3:-}"
	local config_file
	local log_file
	local file_opts
	local wan_dev
	local hostname
	local status_output
	config_file=$(mktemp -t "VERIFY-${service_name}-XXXXXXX")
	log_file=$(get_service_log_filename "$service_name" "openvpn" "verify")
	# wir benoetigen die template-Datei fuer das Erzeugen der Basis-Konfiguration
	prepare_openvpn_service "$service_name"
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
	if grep -q "^proto[ \t]\+tcp" "$config_file"; then
		echo "connect-retry 1"
		echo "connect-timeout 15"
		echo "connect-retry-max 1"
	fi >>"$config_file"

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
	grep -q "Initial packet" "$log_file" && return 0
	msg_debug "openvpn test failed: openvpn $file_opts"
	trap "" $GUARD_TRAPS && return 1
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
	[ -z "$cert_file" -o -z "$key_file" ] && return 0
	# existiert die Datei?
	[ -e "$cert_file" -a -e "$key_file" ] && return 0
	trap "" $GUARD_TRAPS && return 1
}


## @fn has_openvpn_credentials_by_template()
## @brief Prüft, ob der Nutzer bereits einen Schlüssel und ein Zertifikat angelegt hat.
## @param template_file Name einer openvpn-Konfigurationsdatei (oder einer Vorlage). Aus dieser Datei werden "cert"- und "key"-Werte entnommen.
## @returns Liefert "wahr", falls Schlüssel und Zertifikat vorhanden sind oder falls in irgendeiner Form Unklarheit besteht.
has_openvpn_credentials_by_template() {
	trap "error_trap has_openvpn_credentials_by_template '$*'" $GUARD_TRAPS
	local template_file="$1"
	local cert_file
	local key_file
	local base_dir
	cert_file=$(_get_file_dict_value "cert" "$template_file")
	key_file=$(_get_file_dict_value "key" "$template_file")
	# Pruefe, ob eine "cd"-Direktive enthalten ist - vervollständige damit relative Pfade
	base_dir=$(_get_file_dict_value "cd" "$template_file")
	[ -n "$base_dir" -a "${cert_file:0:1}" != "/" ] && cert_file="$base_dir/$cert_file"
	[ -n "$base_dir" -a "${key_file:0:1}" != "/" ] && key_file="$base_dir/$key_file"
	# im Zweifel: liefere "wahr"
	[ -z "$key_file" -o -z "$cert_file" ] && return 0
	# beide Dateien existieren
	[ -e "$key_file" -a -e "$cert_file" ] && return 0
	trap "" $GUARD_TRAPS && return 1
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
	service_name=$(basename "${config%.conf}")
	pid_file=$(get_service_value "$service_name" "pid_file")
	established_indicator_file=$(get_service_value "$service_name" "openvpn_established_indicator_file")
	if [ -z "$established_indicator_file" ]; then
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
			[ -z "${time_duration:-}" ] && time_duration=$(($(date +%s) - $daemon_start_time))
			# Verbindungsverlust durch fehlende openvpn-Pings?
			if [ "${signal:-}" = "ping-restart" ]; then
				append_to_custom_log "$log_target" "down" \
					"Lost connection with ${remote_1}:${remote_port_1} after ${time_duration}s"
				# Verbindung als unklar definieren
				set_service_value "$service_name" "status" ""
				set_service_value "$service_name" "status_timestamp" "$(get_uptime_minutes)"
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


## @fn prepare_openvpn_service()
## @param Name eines Diensts
## @brief Erzeuge oder aktualisiere einen OpenVPN-Dienst
prepare_openvpn_service() {
	trap "error_trap prepare_openvpn_service '$*'" $GUARD_TRAPS
	local service_name="$1"
	local pid_file="/var/run/${service_name}.pid"
	local config_file="$OPENVPN_CONFIG_BASEDIR/${service_name}.conf"
	local service_type
	local template_file
	service_type=$(get_service_value "$service_name" "service")
	# Diese Stelle ist hier eigentlich falsch, da sie Kenntnisse und Variablen
	# vorraussetzt, die nicht in "on-core" definiert sind.
	# Aufgrund der Wiederverwendung der generischen
	# "run_cyclic_service_tests"-Funktion ist eine Separierung dieser Auswahl
	# jedoch leider nur mit großem Aufwand möglich.
	if [ "$service_type" = "gw" ]; then
		template_file="$MIG_OPENVPN_CONFIG_TEMPLATE_FILE"
	elif [ "$service_type" = "mesh" ]; then
		template_file="$MESH_OPENVPN_CONFIG_TEMPLATE_FILE"
	else
		msg_error "unknown service type for openvpn config preparation: $service_type"
		return 1
	fi
	set_service_value "$service_name" "template_file" "$template_file"
	set_service_value "$service_name" "config_file" "$config_file"
	set_service_value "$service_name" "pid_file" "$pid_file"
}


## @fn openvpn_get_mtu()
## @brief Ermittle die MTU auf dem Weg zum Anbieter des Diensts.
## @details The output can be easily parsed via 'cut'. Even the full status output of openvpn is safe for parsing since potential tabulator characters are removed.
## @returns One line consisting of five fields separated by tab characters is returned (tried_to_remote real_to_remote tried_from_remote real_from_remote full_status_output). Failed tests are indicated by an empty result.
openvpn_get_mtu() {
	trap "error_trap openvpn_get_mtu '$*'" $GUARD_TRAPS
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
	local pid="$(cat "$pid_file")"
	local wait_loops=40
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
		elif [ -z "$pid" -o ! -d "/proc/$pid" ]; then
			msg_info "Failed to verify MTU resctrictions for '$host'"
			break
		fi
		sleep 10
		: $((wait_loops--))
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
##   1) nach einem reboot wurde nicht du zuletzt aktive openvpn-Verbindung ausgewählt - somit bleibt der vorher aktive uci-Konfigurationseintrag erhalten
##   2) ein VPN-Verbindungsaufbau scheitert und hinterlässt einen uci-Eintrag, eine PID-Datei, jedoch keinen laufenden Prozess
cleanup_stale_openvpn_services() {
	trap "error_trap cleanup_stale_openvpn_services '$*'" $GUARD_TRAPS
	local service_name
	local config_file
	local pid_file
	local uci_prefix
	find_all_uci_sections openvpn openvpn | while read uci_prefix; do
		config_file=$(uci_get "${uci_prefix}.config")
		# Keine config-Datei? Keine von uns verwaltete Konfiguration ...
		[ -z "$config_file" ] && continue
		service_name="${uci_prefix#openvpn.}"
		# Es scheint sich um eine von uns verwaltete Verbindung zu handeln.
		# Das "pid_file"-Attribut ist nicht persistent - nach einem Neustart kann es also leer sein.
		pid_file=$(get_service_value "$service_name" "pid_file")
		# Falls die config-Datei oder die pid-Datei fehlt, dann ist es ein reboot-Fragment. Wir löschen die Überreste.
		if [ ! -e "$config_file" -o -z "$pid_file" -o ! -e "$pid_file" ]; then
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
