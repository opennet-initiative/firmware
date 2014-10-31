function get_gateway_flag(ip, key)
  local result = luci.sys.exec("on-functions get_gateway_value '"..ip.."' '"..key.."'")
  if result == "" then
    return nil
  else
    return result
  end
end


function set_gateway_flag(ip, key, value)
  if not value then
    value = ""
  end
  luci.sys.exec("on-functions set_gateway_value '"..ip.."' '"..key.."' '"..value.."'")
end

function delete_gateway_flag(ip, key)
  set_gateway_flag(ip, key, "")
end


function get_default_value(domain, key)
	local func_name
	if domain == "on-openvpn" then
		func_name = "get_on_openvpn_default"
	elseif domain == "on-usergw" then
		func_name = "get_on_usergw_default"
	else
		return nil
	end
	local result = luci.sys.exec("on-functions '"..func_name.."' '"..ip.."' '"..key.."'")
	if result == "" then
		return nil
	else
		return result
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
		if (uciconfig == "on-openvpn") then	
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

