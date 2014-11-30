-- Vorsicht: "parameters" wird nicht geprueft/maskiert - vorher gruendlich pruefen!
function on_function(func_name, parameters)
	if not parameters then
		return trim_string(luci.sys.exec("on-function '"..func_name.."'"))
	else
		return trim_string(luci.sys.exec("on-function '"..func_name.."' "..parameters))
	end
end


-- Vorsicht: "parameters" wird nicht geprueft/maskiert - vorher gruendlich pruefen!
function on_bool_function(func_name, parameters)
	return os.execute("on-function '"..func_name.."' "..parameters) == 0
end


function uci_is_true(value)
	return on_bool_function("uci_is_true", "'"..value.."'")
end


function uci_is_false(value)
	return on_bool_function("uci_is_false", "'"..value.."'")
end


function get_service_detail(service_name, key, default)
	local result
	if not default then default = nil end
	result = on_function("get_service_detail", "'"..service_name.."' '"..key.."'")
	if result == "" then return default else return result end
end


function get_service_age(service_name)
	local result = on_function("get_service_age", service_name)
	if result == "" then return nil else return result end
end


function get_service_value(service_name, key, default)
  if not default then default = "" end
  local result = on_function("get_service_value", "'"..service_name.."' '"..key.."' '"..default.."'")
  if result == "" then return nil else return result end
end


function set_service_value(service_name, key, value)
  if not value then
    value = ""
  end
  on_function("set_service_value", "'"..service_name.."' '"..key.."' '"..value.."'")
end


function delete_service_value(service_name, key)
  set_service_value(service_name, key, "")
end


function get_default_value(domain, key)
	local func_name
	if domain == "on-openvpn" then
		func_name = "get_on_openvpn_default"
	elseif domain == "on-usergw" then
		func_name = "get_on_usergw_default"
	elseif domain == "on-wifidog" then
		func_name = "get_on_wifidog_default"
	else
		return nil
	end
	local result = on_function(func_name, "'"..key.."'")
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

