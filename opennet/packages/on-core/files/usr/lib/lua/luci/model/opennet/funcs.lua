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
	return on_bool_function("uci_is_true", {text or ""})
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


function get_html_loading_spinner(name, style)
	return '<span id="' .. name .. '"><img class="loading_img_small"' ..
			' src="' .. html_resource_base .. '/icons/loading.gif" alt="' ..
			luci.i18n.translate("Loading") .. '" style="' .. (style or "") .. '" /></span>'
end


--- @brief Liefere eine begrenzte Anzahl von Zeilen eines Logs zurück (umgekehrt sortiert von neu zu alt).
--- @param log_name Name des Log-Ziels
--- @param lines Anzahl der zurückzuliefernden Zeilen
function get_custom_log_reversed(log_name, lines)
	return luci.sys.exec("on-function get_custom_log '" .. log_name .. "' | tail -n '" .. lines .. "' | tac")
end


function get_services_sorted_by_priority(service_type)
	return luci.sys.exec("on-function get_services '" .. service_type .. "' | on-function sort_services_by_priority")
end


function _generic_split(text, token_regex)
	local result = {}
	local token
	for token in text:gmatch(token_regex) do table.insert(result, token) end
	return result
end


function tab_split(text) return _generic_split(text, "[^\t]+") end
function line_split(text) return _generic_split(text, "[^\n]+") end
function space_split(text) return _generic_split(text, "%S+") end
function dot_split(text) return _generic_split(text, "[^.]+") end


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
	local token
	local dummy
	for dummy, token in ipairs(table) do
		if result then
			result = result .. separator .. token
		else
			result = token
		end
	end
	return result
end


function to_bool(value)
	if value then
		return true
	else
		return false
	end
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
fuelle die extern definierte Variable "openssl" mit Werten aus den Konfigurationsdateien
"domain" ist "on-openvpn" oder "on-usergw" (siehe auch "get_default_value")
]]--
function fill_openssl(domain, openssl)
	local uci = require("luci.model.uci")
	local cursor = uci.cursor()
	openssl.countryName = get_default_value(domain, "certificate_countryName")
	openssl.provinceName = get_default_value(domain, "certificate_provinceName")
	openssl.localityName = get_default_value(domain, "certificate_localityName")
	openssl.organizationalUnitName = get_default_value(domain, "certificate_organizationalUnitName")
	openssl.organizationName = luci.http.formvalue("openssl.organizationName")
	openssl.commonName = luci.http.formvalue("openssl.commonName")
	if not openssl.commonName then
		on_id = cursor:get("on-core", "settings", "on_id")
		if not on_id then on_id = "X.XX" end
		if (domain == "on-openvpn") then
			openssl.commonName = on_id..".aps.on"
		else
			openssl.commonName = on_id..".ugw.on"
		end
	end
	openssl.EmailAddress = luci.http.formvalue("openssl.EmailAddress")
	openssl.days = get_default_value(domain, "certificate_days")
end


function generate_csr(type, openssl)
	local filename = "on_aps"
	if type == "mesh" then filename = "on_ugws" end
	if openssl.organizationName and openssl.commonName and openssl.EmailAddress then
		local command = "export openssl_countryName='"..openssl.countryName.."'; "..
						"export openssl_provinceName='"..openssl.provinceName.."'; "..
						"export openssl_localityName='"..openssl.localityName.."'; "..
						"export openssl_organizationalUnitName='"..openssl.organizationalUnitName.."'; "..
						"export openssl_organizationName='"..openssl.organizationName.."'; "..
						"export openssl_commonName='"..openssl.commonName.."'; "..
						"export openssl_EmailAddress='"..openssl.EmailAddress.."'; "..
						"openssl req -config /etc/ssl/on_openssl.cnf -batch -nodes -new -days "..openssl.days..
							" -keyout "..SYSROOT.."/etc/openvpn/opennet_"..type.."/"..filename..".key"..
							" -out "..SYSROOT.."/etc/openvpn/opennet_"..type.."/"..filename..".csr >/tmp/ssl.out"
		os.execute(command)
		nixio.fs.chmod(SYSROOT.."/etc/openvpn/opennet_"..type.."/"..filename..".key", 600)
		nixio.fs.chmod(SYSROOT.."/etc/openvpn/opennet_"..type.."/"..filename..".csr", 600)
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


--- @brief Liefere den HTML-Code für eine Fehlerausgabe zurück.
--- @param text Fehlertext
--- @returns ein html-String
function html_error_box(text)
	return '<div class="errorbox"><h4>' .. luci.i18n.translatef("Error: %s", luci.util.pcdata(text)) .. '</h4></div>'
end


--[[
@brief Liefere den HTML-Code für eine potentielle Liste von Fehlern zurück.
@param errors eine Table mit Fehlermeldungen
@returns ein html-String
--]]
function html_display_error_list(errors)
	local result = ""
	for _, value in pairs(errors or {}) do
		result = result .. html_error_box(value)
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
@param key_type Der Zertifikatstyp ("user" oder "mesh") ist für die Auswahl des Zielverzeichnis relevant.
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
function process_openvpn_certificate_form(key_type)
    require("luci.model.opennet.on_vpn_management")

    local result = {}

    if luci.http.formvalue("upload") then upload_file(key_type) end

    local download = luci.http.formvalue("download")
    if download then download_file(key_type, download) end

    local openssl = {}
    local openssl_domain
    if key_type == "user" then
        openssl_domain = "on-openvpn"
    elseif key_type == "mesh" then
        openssl_domain = "on-usergw"
    end
    fill_openssl(openssl_domain, openssl)

    if luci.http.formvalue("generate") then generate_csr(key_type, openssl) end

    local certstatus = {}
    check_cert_status(key_type, certstatus)

    result.force_show_uploadfields = luci.http.formvalue("force_show_uploadfields") or not certstatus.on_keycrt_ok
    result.force_show_generatefields = luci.http.formvalue("force_show_generatefields") or (not certstatus.on_keycrt_ok and not certstatus.on_keycsr_ok)
    result.certstatus = certstatus
    result.openssl = openssl

    return result
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
