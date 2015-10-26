--- @defgroup lua Lua-Funktionen
-- Beginn der Doku-Gruppe
--- @{

require "luci.config"
require "luci.util"


html_resource_base = luci.config.main.resourcebase
SYSROOT = os.getenv("LUCI_SYSROOT") or ""


function _quote_parameters(parameters)
	local arguments = ""
	local value
	local dummy
	if parameters then
		for dummy, value in pairs(parameters) do
			arguments = arguments .. " '" .. value .. "'"
		end
	end
	return arguments
end


function on_function(func_name, parameters)
	local cmdline = "on-function '" .. func_name .. "' " .. _quote_parameters(parameters)
	return trim_string(luci.sys.exec(cmdline))
end


function on_bool_function(func_name, parameters)
	local cmdline = "on-function '" .. func_name .. "' " .. _quote_parameters(parameters)
	return luci.sys.call(cmdline) == 0
end


--- @brief Interpretiere einen Text entsprechend der uci-Boolean-Definition (yes/y/true/1 = wahr).
--- @param text textuelle Repräsentation eines Wahrheitswerts
--- @returns true oder false
--- @details Leere oder nicht erkannte Eingaben werden als "false" gewertet.
function uci_to_bool(text)
	-- synchron halten mit Funktion "uci_is_false" (shell-Module)
	if (text == "0") or (text == "no") or (text == "n") or (text == "off") or (text == "false") then
		return false
	else
		return true
	end
end


--- @brief Liefere zu einem boolean-Wert das html-geeignete "y" / "n" oder "" zurück.
--- @param value Eingangswert: entweder ein boolean-Wert oder ein String, der als "uci boolean" interpretiert wird.
--- @returns "y" / "n" oder ""
--- @details Leere Eingaben werden mit einem leeren String quittiert. Nicht erkannte Eingaben werden als "false" gewertet.
function bool_to_yn(value)
	if value == true then
		return "y"
	elseif value == false then
		return "n"
	elseif (not value) or (value == "") then
		return ""
	elseif uci_to_bool(value) then
		return "y"
	else
		return "n"
	end
end


--- @brief Ermittle ob eine table leer ist.
--- @param table Die zu prüfende Tabelle.
function table_is_empty(data)
	for _, _ in ipairs(data) do
		return false
	end
	return true
end


function get_html_loading_spinner(name, style)
	return '<span id="' .. name .. '"><img class="loading_img_small"' ..
			' src="' .. html_resource_base .. '/icons/loading.gif" alt="' ..
			luci.i18n.translate("Loading") .. '" style="' .. (style or "") .. '" /></span>'
end


--- @brief Liefere eine begrenzte Anzahl von Zeilen eines Logs zurück (umgekehrt sortiert von neu zu alt).
--- @param log_name Name des Log-Ziels
--- @param lines Anzahl der zurückzuliefernden Zeilen
function get_custom_log_reversed(log_name, lines)
	-- die "sed"-Komponente kehrt die Reihenfolge der Zeilen um (http://stackoverflow.com/a/744093)
	-- Dies erspart uns die Abhaengigkeit gegen das passendere "tac".
	return luci.sys.exec("on-function get_custom_log_content '" .. log_name .. "' | tail -n '" .. lines .. "' | sed -n '1!G;h;$p'")
end


function get_services_sorted_by_priority(service_type)
	return luci.sys.exec("on-function get_services '" .. service_type .. "' | on-function sort_services_by_priority")
end


--- @brief Füge eine Warnung zur gegebenen "errors"-Tabelle hinzu, falls das angegebene Modul derzeit abgeschaltet ist.
--- @param module_name Name eines Opennet-Moduls, dessen Aktivierungszustand geprüft werden soll
--- @param errors Liste von Fehlern, die eventuell erweitert wird
--- @details Jede Seite eines Opennet-Moduls sollte eine Fehlerausgabe vorsehen. In der dazugehörigen controller-Funktion
---    sollte diese Funktion aufgerufen werden.
function check_and_warn_module_state(module_name, errors)
	if not on_bool_function("is_on_module_installed_and_enabled", {module_name}) then
		table.insert(errors, luci.i18n.translatef(
			[[The module '%s' is currently disabled (see 'Opennet -> Base -> Settings').]], module_name))
	end
end


--- @fn generic_split()
--- @brief Teile eine Zeichenkette anhand eines gegebenen regulären Ausdrucks, der die
---   Zusammensetzung eines Token (nicht des Trennzeichens) beschreibt.
--- @param text Der zu teilende Text.
--- @param token_regex Der reguläre Ausdruck, der ein Token beschreibt (z.B. '[^ ]+' für Leerzeichen-getrennte Token).
function generic_split(text, token_regex)
	local result = {}
	local token
	if text then
		for token in text:gmatch(token_regex) do table.insert(result, token) end
	end
	return result
end


function tab_split(text) return generic_split(text, "[^\t]+") end
function line_split(text) return generic_split(text, "[^\n]+") end
function space_split(text) return generic_split(text, "%S+") end
function dot_split(text) return generic_split(text, "[^.]+") end


function map_table(input_table, func)
	local dummy
	local value
	local result = {}
	for dummy, value in ipairs(input_table) do
		table.insert(result, func(value))
	end
	return result
end


-- Fuege die Elemente einer String-Liste mittels eines Separators zusammen.
-- Eine leere Liste fuehrt zum Ergebnis 'nil'.
function string_join(table, separator)
	local result
	for _, token in ipairs(table) do
		if result then
			result = result .. separator .. token
		else
			result = token
		end
	end
	return result
end


function get_service_value(service_name, key, default)
	if not default then default = "" end
	local result = on_function("get_service_value", {service_name, key, default})
	if result == "" then return nil else return result end
end


function set_service_value(service_name, key, value)
	if not value then value = "" end
	on_function("set_service_value", {service_name, key, value})
end


function delete_service_value(service_name, key)
	set_service_value(service_name, key, "")
end


function get_default_value(domain, key)
	local func_name
	if domain == "on-core" then
		func_name = "get_on_core_default"
	elseif domain == "on-openvpn" then
		func_name = "get_on_openvpn_default"
	elseif domain == "on-usergw" then
		func_name = "get_on_usergw_default"
	elseif domain == "on-captive-portal" then
		func_name = "get_on_captive_portal_default"
	else
		return nil
	end
	local result = on_function(func_name, {key})
	if result == "" then
		return nil
	else
		return result
	end
end


function trim_string(s)
	if not s then
		return s
	else
		return (s:gsub("^%s*(%S+)%s*$", "%1"))
	end
end


--[[
fuelle eine table mit Werten aus den Konfigurationsdateien
"cert_type" ist "user" oder "mesh"
]]--
function get_openssl_csr_presets(cert_type)
	local cert_info = get_ssl_cert_info(cert_type)
	local defaults_domain = cert_info.on_package
	local result = {}
	result.countryName = get_default_value(defaults_domain, "certificate_countryName")
	result.provinceName = get_default_value(defaults_domain, "certificate_provinceName")
	result.localityName = get_default_value(defaults_domain, "certificate_localityName")
	result.organizationalUnitName = get_default_value(defaults_domain, "certificate_organizationalUnitName")
	result.days = get_default_value(defaults_domain, "certificate_days")
	result.commonName = on_function("uci_get", {"on-core.settings.on_id", "X.XX"}) .. cert_info.common_name_suffix
	return result
end


function get_ssl_cert_info(cert_type)
	local result = {}
	if cert_type == "mesh" then
		result.cert_dir = SYSROOT .. "/etc/openvpn/opennet_ugw"
		result.filename_prefix = result.cert_dir .. "/" .. "on_ugws"
		result.on_package = "on-usergw"
		result.common_name_suffix = ".ugw.on"
	elseif cert_type == "user" then
		result.cert_dir = SYSROOT .. "/etc/openvpn/opennet_user"
		result.filename_prefix = result.cert_dir .. "/" .. "on_aps"
		result.on_package = "on-openvpn"
		result.common_name_suffix = ".aps.on"
	end
	return result
end


function generate_csr(cert_type, openssl)
	local cert_info = get_ssl_cert_info(cert_type)
	if openssl.organizationName and openssl.commonName and openssl.EmailAddress then
		nixio.fs.mkdirr(cert_info.cert_dir)
		local command = "export openssl_countryName='"..openssl.countryName.."'; "..
						"export openssl_provinceName='"..openssl.provinceName.."'; "..
						"export openssl_localityName='"..openssl.localityName.."'; "..
						"export openssl_organizationalUnitName='"..openssl.organizationalUnitName.."'; "..
						"export openssl_organizationName='"..openssl.organizationName.."'; "..
						"export openssl_commonName='"..openssl.commonName.."'; "..
						"export openssl_EmailAddress='"..openssl.EmailAddress.."'; "..
						"openssl req -config /etc/ssl/on_openssl.cnf -batch -nodes -new -days "..openssl.days..
							" -keyout ".. cert_info.filename_prefix .. ".key"..
							" -out ".. cert_info.filename_prefix .. ".csr >/tmp/ssl.out"
		os.execute(command)
		nixio.fs.chmod(cert_info.filename_prefix .. ".key", 600)
		nixio.fs.chmod(cert_info.filename_prefix .. ".csr", 600)
	end
end


function get_private_key_id(cert_type)
	local cert_info = get_ssl_cert_info(cert_type)
	local filename = cert_info.filename_prefix .. ".key"
	if nixio.fs.stat(filename) then
		local id_output = trim_string(luci.sys.exec("openssl rsa -modulus -noout <'" .. filename .. "'"))
		return generic_split(id_output, "[^=]+")[2]
	else
		return nil
	end
end


--[[
-- Einlesen und Typ-konvertieren von CSV-Ausgaben der 'get_service_as_csv'-Funktion (shell-Bibliothek).
-- Dies ermöglicht die effiziente Sammlung der relevanten Informationen für jeden Dienst mit nur einem
-- Fork für den Funktionsaufruf. Die einzelne Abfrage aller Informationen dauert dagegen viel länger.
-- Parameter service_name: der Name eines Diensts
-- Parameter descriptions: eine table von Informationsbeschreibungen (z.B.: offset="number|value|offset")
-- Der Rückgabewert ist eine table mit benannten Parametern.
-- Leere Strings werden als nil zurückgeliefert.
--]]
function parse_csv_service(service_name, descriptions)
	local name
	local token
	local result_string
	local order = {}
	local specifications = {}
	local arguments = {}
	local one_service = {}
	local index = 0
	table.insert(arguments, service_name)
	-- arguments, order und specifications fuellen
	for name, value in pairs(descriptions) do
		table.insert(order, name)
		specifications[name] = value
		table.insert(arguments, value)
	end
	result_string = on_function("get_service_as_csv", arguments)
	if result_string == "" then return nil end
	-- das abschliessende Semikolon erleichtert den regulaeren Ausdruck
	for token in string.gmatch(result_string .. ";", "([^;]*);") do
		if index == 0 then
			one_service["id"] = token
		else
			name = order[index]
			if name then
				value = specifications[name]
				if token == "" then
					token = nil
				elseif string.sub(value, 1, 7) == "number|" then
					token = tonumber(token)
				elseif string.sub(value, 1, 5) == "bool|" then
					token = (token == "true")
				end
				one_service[name] = token
			end
		end
		index = index + 1
	end
	return one_service
end


--- @brief Zahl aus einer Zeichenkette herausfiltern (sinnvoll für freie Texteingaben).
--- @param text Zeichenkette (oder nil) die Ziffern enthalten sollte.
--- @returns nil (leere Eingabe oder keine Zahl enthalten) bzw. der String der die Ziffern enthält
function parse_number_string(text)
	return string.match(text or "", "%d+")
end


--- @brief Hostnamen, bzw. IP aus einer Zeichenkette herausfiltern.
--- @param text Zeichenkette (oder nil) die einen Hostnamen oder eine IP enthalten sollte.
--- @returns nil bzw. der gefilterte String
function parse_hostname_string(text)
	local text = text or ""
	-- IPv4/IPv6 oder Hostname (sehr tolerante Filter - ausreichend fuer die Erkennung boeser Eingaben)
	return string.match(text, "^[0-9A-Fa-f:.]$") or string.match(text, "^[a-zA-Z0-9.-]+$")
end


--[[
@brief Liefere die um führende oder abschließende Leerzeichen bereinigte Zeichenkette zurück, sofern nur die angegebenen Zeichen enthalten sind.
@param text die zu filternde Zeichenkette
@param characters eine Reihe gültiger Zeichen im Format eines regex-Zeichensatzes (z.B. "a-zA-Z").
@details Auch ein leerer String (also null gültige Zeichen) ist zulässig, solange keine unzulässigen Zeichen vorgefunden werden.
--]]
function parse_string_pattern(text, characters)
	if not text then return nil end
	return string.match(text, "^%s*[" .. characters .. "]*%s*$")
end


--- @brief Liefere den HTML-Code für eine Fehlerausgabe oder Hinweise zurück.
--- @param text Fehlertext
--- @param class Nachrichten-Klasse (error / info)
--- @returns ein html-String
function html_box(text, class)
	local split_out
	local _
	split_out, _ = string.gsub(luci.util.pcdata(text), "\n", "<br/>")
	local prefix
	local css_class
	if class == "error" then
		prefix = luci.i18n.translate("Error: ")
		css_class = "errorbox"
	else
		prefix = ""
		-- "infobox" ist eine opennet-spezifische css-Klasse
		css_class = "infobox"
	end
	return '<div class="' .. css_class .. '"><h4>' .. prefix .. split_out .. '</h4></div>'
end


--[[
@brief Liefere den HTML-Code für eine Liste von Meldungen zurück.
@param messages eine Table mit Fehlermeldungen oder Hinweisen
@param class Nachrichten-Klasse (error / info)
@returns ein html-String
--]]
function html_display_message_list(messages, class)
	local result = ""
	for _, value in pairs(messages or {}) do
		if value and value ~= "" then
			result = result .. html_box(value, class)
		end
	end
	return result
end


--[[
@brief Verarbeite ein HTML-Formular und erzeuge - falls möglich - einen neuen Dienst aus den gegebenen Informationen.
@details Die folgenden HTML-Formularvariablen werden verarbeitet:
    add_service: für nil findet keine weitere Verarbeitung statt
    service_host: der Hostname oder die IP des Diensts
    service_port: der Port des Diensts (eine Zahl)
    service_scheme: Dienst-Schema (z.B. 'openvpn' - nur Kleinbuchstaben)
    service_protocol: Dienst-Protokoll (udp/tcp - nur Kleinbuchstaben)
    service_type: die Art des angebotenen Diensts (z.B. "mesh", "dns" oder "igw")
    service_path: eine Pfad-Angabe für den Dienst, falls erforderlich (typischerweise "/")
    service_details: zusätzliche Details für den Dienst
  Falls irgendeiner dieser Parameter fehlt oder unübliche Zeichen enthält, dann liefert
  die Funktion als Ergebnis eine Fehlermeldung zurück.
@returns Im Fehlerfall liefert die Funktion einen Fehlertext zurück.
  Im Erfolgsfall ist das Ergebnis 'true' (Änderungen wurden vorgenommen) oder 'false' (keine Änderungen).
--]]
function process_add_service_form()
    local add_service = luci.http.formvalue("add_service")
    local host = luci.http.formvalue("service_host")
    local port = luci.http.formvalue("service_port")
    local scheme = luci.http.formvalue("service_scheme")
    local protocol = luci.http.formvalue("service_protocol")
    local stype = luci.http.formvalue("service_type")
    local path = luci.http.formvalue("service_path")
    local priority = luci.http.formvalue("service_priority")
    local details = luci.http.formvalue("service_details")

    if add_service and host and port and protocol and stype and path and details then
        host = parse_hostname_string(host)
	if not host then return luci.i18n.translate("Invalid host") end
        port = parse_number_string(port)
	if not port then return luci.i18n.translate("Invalid port") end
	if (protocol ~= "udp") and (protocol ~= "tcp") then return luci.i18n.translate("Unknown protocol") end
	scheme = parse_string_pattern(scheme, "a-z")
	if not scheme then return luci.i18n.translate("Invalid service scheme") end
	stype = parse_string_pattern(stype, "a-z")
	if not stype then return luci.i18n.translate("Invalid service type") end
	path = parse_string_pattern(path, "a-zA-Z0-9._/-")
	if not path then return luci.i18n.translate("Invalid path") end
	details = parse_string_pattern(details, "a-zA-Z0-9._/:%s-")
	if not details then return luci.i18n.translate("Invalid service details") end
        local service_name = on_function("notify_service", {stype, scheme, host, port, protocol, path, "manual", details})
	-- die Prioritaet wird nur gesetzt, falls sie uebergeben wurde (z.B. fuer Mesh-Gateways)
	if priority and (priority ~= "") then
		priority = parse_number_string(priority)
		if priority then set_service_value(service_name, "priority", priority) end
	end
	return true
    else
        return false
    end
end


--[[
@brief Verarbeite ein HTML-Formular und führe die angeforderten Aktionen für Dienste aus.
@param service_type Der Dienst-Typ (z.B. "mesh" oder "gw") ist für die Änderung der Reihenfolge notwendig.
@details Die folgenden HTML-Formularvariablen werden verarbeitet:
    move_up/move_down/move_top/delete/disable/enable/reset_offset
  Diese Variablen werden jeweils als Dienstname interpretiert und lösen die Anwendung der im
  Variablennamen angedeuteten Aktion aus. Die Verschiebungen (move_up|down|top) beziehen sich
  dabei jeweils auf den als Paramter übergebenen 'service_type'.
  Falls irgendeiner dieser Parameter fehlt oder unübliche Zeichen enthält, dann liefert
  die Funktion als Ergebnis eine Fehlermeldung zurück.
@returns Im Fehlerfall liefert die Funktion einen Fehlertext zurück.
  Im Erfolgsfall ist das Ergebnis 'true' (Änderungen wurden vorgenommen) oder 'false' (keine Änderungen).
--]]
function process_service_action_form(service_type)
    filter_func = function(text) return parse_string_pattern(text, "a-zA-Z0-9_") end
    local move_up = filter_func(luci.http.formvalue("move_service_up"))
    local move_down = filter_func(luci.http.formvalue("move_service_down"))
    local move_top = filter_func(luci.http.formvalue("move_service_top"))
    local delete = filter_func(luci.http.formvalue("delete_service"))
    local disable = filter_func(luci.http.formvalue("disable_service"))
    local enable = filter_func(luci.http.formvalue("enable_service"))
    local reset_offset = filter_func(luci.http.formvalue("reset_service_offset"))

    -- Prüfe alle Eingaben auf ihre Tauglichkeit als Dienst-Name.
    -- Dies ist nicht relevant für die Funktionalität (da die Eingaben ohnehin gefiltert werden),
    -- sondern eher eine Debug-Hilfe.
    for _, key in pairs({"move_service_up", "move_service_down", "move_service_top",
            "delete_service", "disable_service", "enable_service", "reset_service_offset"}) do
        local value = luci.http.formvalue(key)
	if value and (value ~= filter_func(value)) then
            return luci.i18n.translate("Service Action: Invalid service name")
        end
    end
     
    -- Prüfe, ob 'move'-Aktionen von einem 'service_type' begleitet werden - andernfalls melden wir einen Fehler.
    if not service_type and (move_up or move_down or move_top) then
        return luci.i18n.translate("Service Action: missing 'service_type' for 'move' action")
    end

    if move_up or move_down or move_top or delete or disable or enable or reset_offset then
        if move_up then
            on_function("move_service_up", {move_up, service_type})
        end
        if move_down then
            on_function("move_service_down", {move_down, service_type})
        end
        if move_top then
            on_function("move_service_top", {move_top, service_type})
        end
        if delete then
            on_function("delete_service", {delete})
        end
        if disable then
            set_service_value(disable, "disabled", "1")
        end
        if enable then
            delete_service_value(enable, "disabled")
        end
        if reset_offset then
            delete_service_value(reset_offset, "offset")
        end
        return true
    else
        return false
    end
end


--[[
@brief Verarbeite ein HTML-Formular und führe die angeforderten Aktionen für OpenVPN-Zertifikate aus.
@param cert_type Der Zertifikatstyp ("user" oder "mesh") ist für die Auswahl des Zielverzeichnis relevant.
@details Die folgenden HTML-Formularvariablen werden verarbeitet:
    force_show_uploadfields: Nutzereingabe erzwingt die Anzeige des Upload-Formulars
    force_show_generatefields: Nutzereingabe erzwingt die Anzeige des "Erzeuge CSR"-Formulars
    upload: zu importierende Datei (@see upload_file)
    download: zu exportierende Datei (@see download_file)
    generate: soll ein CSR erzeugt werden? (dabei werden weitere Attribute ausgelesen - @see generate_csr)
@returns Eine table mit den folgenden Werten wird zurückgegeben:
    openssl: Werte zum Ausfüllen des CSR-Dialogs ("Organization", usw.)
    certstatus: Auswertung des Zertifikatszustands (@see check_cert_status)
    force_show_uploadfields: Soll die Anzeige des Datei-Upload-Formulars erzwungen werden?
    force_show_generatefields: Soll die Anzeige des CSR-Erzeugen-Formulars erzwungen werden?
--]]
function process_openvpn_certificate_form(cert_type)
    require("luci.model.opennet.on_vpn_management")

    local result = {}

    if luci.http.formvalue("upload") then upload_file(cert_type) end

    local download = luci.http.formvalue("download")
    if (download == "csr") or (download == "crt") or (download == "key") then download_file(cert_type, download) end

    local openssl = get_openssl_csr_presets(cert_type, openssl)
    openssl.organizationName = trim_string(luci.http.formvalue("openssl.organizationName"))
    openssl.EmailAddress = trim_string(luci.http.formvalue("openssl.EmailAddress"))
    local form_cn = trim_string(luci.http.formvalue("openssl.commonName")) 
    if form_cn and (form_cn ~= "") then openssl.commonName = form_cn end

    local certstatus = check_cert_status(cert_type)

    -- prüfe ob zwischenzeitlich ein (anderes) CSR erzeugt wurde (z.B. beim Verwenden der "zurück"-Funktion des Browsers)
    if luci.http.formvalue("generate") then
        if luci.http.formvalue("confirm_overwrite_key_id") == certstatus.on_key_modulus then
            generate_csr(cert_type, openssl)
        end
    end


    result.force_show_uploadfields = luci.http.formvalue("force_show_uploadfields") or not certstatus.on_keycrt_ok
    result.force_show_generatefields = luci.http.formvalue("force_show_generatefields") or (not certstatus.on_keycrt_ok and not certstatus.on_keycsr_ok)
    result.certstatus = certstatus
    result.openssl = openssl

    return result
end


--[[
@brief Liefere wahr zurueck, falls das CSR hochgeladen werden sollte und sofern dies erfolgreich verlief.
@details Im Erfolgsfall wurde bereits eine html-Ausgabe geschrieben - die aufrufende Funktion kann anschliessend ohne weitere
  Ausgabe beendet werden. Eventuelle Fehler werden in 'errors_table' eingefuegt.
--]]
function process_csr_submission(cert_type, errors_table)
    local submit_url = luci.http.formvalue("submit")
    if submit_url then
        local cert_info = get_ssl_cert_info(cert_type)
        local csr_filename = cert_info.filename_prefix .. ".csr"
        -- zeige lediglich die Ausgabe von curl an
        local result = on_function("submit_csr_via_http", {submit_url, csr_filename})
        if result and (result ~= "") then
            -- das Upload-Resultat sollte ausgegeben werden
            luci.http.write(result)
	    -- die wahr-Rueckgabe sollte in der aufrufenden Funktion zum unmittelbaren (fehlerfreien) Ende fuehren
	    return true
        else
            table.insert(errors_table, luci.i18n.translate("Failed to send Certificate Signing Request. You may want to use a manual approach instead. Sorry!"))
        end
    end
    -- keine Rueckgabe - die aufrufende Funktion sollte ihren Ablauf fortsetzen
    return false
end


--[[
@brief Liefere einen String zurück, der das Alter eines Zeitstempels (Sekunden seit Epoch) beschreibt.
@details Die Ausgabe erfolgt entweder als Angabe des Beginns (bei einem alten Zeitstempel) oder 
    in Form von "x Tage und y Stunden" als Abstand zum jetzigen Zeitpunkt.
--]]
function get_timestamp_age_string(timestamp)
	local now = os.time()
	local age = now - timestamp
	if (timestamp > now) or (age > 3600 * 24 * 7) then
		-- in der Zukunft oder älter als eine Woche
		return os.date(luci.i18n.translate("%Y/%m/%d - %H:%M"), timestamp)
	elseif (now - timestamp > 3600 * 24) then
		return luci.i18n.translatef("%d days and %d hours", math.floor(age / (3600 * 24)), math.floor((age / 3600) % 24))
	elseif (now - timestamp > 3600) then
		return luci.i18n.translatef("%d hours and %d minutes", math.floor(age / (60 * 60)), math.floor((age / 60) % 60))
	else
		return luci.i18n.translatef("%d minutes and %d seconds", math.floor(age / 60), math.floor(age % 60))
	end
end

--[[
@brief Liefere einen String zurueck, der eine gewuenschte Funktion an das "onload"-Ereignis der aktuellen Webseite haengt.
@details Diese Funktion sollte innerhalb eines Javascript-Blocks aufgerufen werden.
--]]
function register_javascript_function_onload(func_name)
	return [[
		if (window.attachEvent) {
			window.attachEvent('onload', ]] .. func_name .. [[);
		} else if (window.addEventListener) {
			window.addEventListener('load', ]] .. func_name .. [[, false);
		} else {
			document.addEventListener('load', ]] .. func_name .. [[, false);
		}]]
end

-- Ende der Doku-Gruppe
--- @}
