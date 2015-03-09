--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--

require("luci.sys")
require("luci.http")
require("luci.i18n")

function split(str, pat)
	local t = {}  -- NOTE: use {n = 0} in Lua-5.0
	local fpat = "(.-)" .. pat
	local last_end = 1
	local s, e, cap = str:find(fpat, 1)
	while s do
		if s ~= 1 or cap ~= "" then
		table.insert(t,cap)
		end
		last_end = e+1
		s, e, cap = str:find(fpat, last_end)
	end
	if last_end <= #str then
		cap = str:sub(last_end)
		table.insert(t, cap)
	end
	return t
end

function write_infotable(data)
	luci.http.write("<table class='status_page_table' >")
	local count = 1
	while count < table.getn(on_crt_data) do
		if on_crt_data[count] ~= "subject" then
			luci.http.write("<tr><td>" .. on_crt_data[count] .. "</td><td>" .. on_crt_data[count+1] .. "</td></tr>")
			count = count + 1
		end
		count = count + 1
	end
	luci.http.write("</table></div>")
end

function display_csr_infotable(type)
	local crtname = "/etc/openvpn/opennet_user/on_aps.csr"
	if type == "ugw" then crtname = "/etc/openvpn/opennet_ugw/on_ugws.csr" end
	on_crt_data = split(luci.sys.exec("openssl req -in "..crtname.." -nameopt sep_comma_plus,lname -subject -noout"), '[,=]')
	luci.http.write("<div><h4>" .. luci.i18n.translate("Certificate-Request contents") .. "</h4>")
	write_infotable(on_crt_data)
end
function display_crt_infotable(type)
	local crtname = "/etc/openvpn/opennet_user/on_aps.crt"
	if type == "ugw" then crtname = "/etc/openvpn/opennet_ugw/on_ugws.crt" end
	on_crt_data = split(luci.sys.exec("openssl x509 -in "..crtname.." -nameopt sep_comma_plus,lname -subject -noout"), '[,=]')
	luci.http.write("<div><h4>" .. luci.i18n.translate("Certificate contents") .. "</h4>")
	write_infotable(on_crt_data)
end
