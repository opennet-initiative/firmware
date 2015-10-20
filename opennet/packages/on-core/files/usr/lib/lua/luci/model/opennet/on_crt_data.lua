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
	while count < table.getn(data) do
		if data[count] ~= "subject" then
			luci.http.write("<tr><td>" .. data[count] .. "</td><td>" .. data[count+1] .. "</td></tr>")
			count = count + 1
		end
		count = count + 1
	end
	luci.http.write("</table></div>")
end

function display_csr_infotable(cert_type)
	local cert_info = get_ssl_cert_info(cert_type)
	local filename = cert_info.filename_prefix .. ".csr"
	local on_csr_data = split(luci.sys.exec("openssl req -in " .. filename .. " -nameopt sep_comma_plus,lname -subject -noout"), '[,=\n]')
	luci.http.write("<div><h4>" .. luci.i18n.translate("Certificate Request contents") .. "</h4>")
	write_infotable(on_csr_data)
end

function display_crt_infotable(cert_type)
	local cert_info = get_ssl_cert_info(cert_type)
	local filename = cert_info.filename_prefix .. ".crt"
	local on_crt_data = split(luci.sys.exec("openssl x509 -in " .. filename .. " -nameopt sep_comma_plus,lname -subject -enddate -noout"), '[,=\n]')
	luci.http.write("<div><h4>" .. luci.i18n.translate("Certificate contents") .. "</h4>")
	write_infotable(on_crt_data)
end
