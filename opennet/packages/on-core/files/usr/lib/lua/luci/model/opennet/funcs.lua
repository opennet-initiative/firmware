--- @defgroup lua Lua-Funktionen
-- Beginn der Doku-Gruppe
--- @{

require "luci.config"
html_resource_base = luci.config.main.resourcebase


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
--- @param text textuelle Repräsentation eines Wahrheitswerts
--- @returns "y" / "n" oder ""
--- @details Leere Eingaben werden mit einem leeren String quittiert. Nicht erkannte Eingaben werden als "false" gewertet.
function bool_string_to_yn(value)
	if (not value) or (value == "") then
		return ""
	elseif uci_to_bool(value) then
		return "y"
	else
		return "n"
	end
end


function get_html_loading_spinner(name, style)
	return '<img class="loading_img_small" name="' .. name ..
			'" src="' .. html_resource_base .. '/icons/loading.gif" alt="' ..
			luci.i18n.translate("Loading") .. '" style="display:none;" />'
end


--- @brief Liefere eine begrenzte Anzahl von Zeilen eines Logs zurück (umgekehrt sortiert von neu zu alt).
--- @param log_name Name des Log-Ziels
--- @param lines Anzahl der zurückzuliefernden Zeilen
function get_custom_log_reversed(log_name, lines)
	return luci.sys.exec("on-function get_custom_log '" .. log_name .. "' | tail -n '" .. lines .. "' | tac")
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
	elseif domain == "on-wifidog" then
		func_name = "get_on_wifidog_default"
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
	if type == "ugw" then filename = "on_ugws" end
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

-- Ende der Doku-Gruppe
--- @}
