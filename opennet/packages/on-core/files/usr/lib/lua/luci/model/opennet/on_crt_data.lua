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
require("luci.model.opennet.funcs")


function split_lines_into_table_rows(lines)
	for _, line in ipairs(lines) do
		local key = space_split(line)[1]
		local value = trim_string(string.sub(line, string.len(key) + 1))
		luci.http.write("<tr><td>" .. key .. "</td><td>" .. value .. "</td></tr>")
	end
end


function display_csr_infotable(cert_type)
	local cert_info = get_ssl_cert_info(cert_type)
	local filename = cert_info.filename_prefix .. ".csr"
	luci.http.write("<div><h4>" .. luci.i18n.translate("Certificate Request contents") .. "</h4>")
	luci.http.write('<table class="status_page_table" >')
	split_lines_into_table_rows(line_split(on_function("get_ssl_csr_subject_components", {filename})))
	luci.http.write("</table>")
	luci.http.write("</div>")
end


function display_crt_infotable(cert_type)
	local cert_info = get_ssl_cert_info(cert_type)
	local filename = cert_info.filename_prefix .. ".crt"
	luci.http.write("<div><h4>" .. luci.i18n.translate("Certificate contents") .. "</h4>")
	luci.http.write('<table class="status_page_table" >')
	split_lines_into_table_rows(line_split(on_function("get_ssl_certificate_subject_components", {filename})))
	luci.http.write("<tr><td>" .. luci.i18n.translate("Expiry date") .. "</td><td>"
		.. trim_string(on_function("get_ssl_certificate_enddate", {filename})) .. "</td></tr>")
	luci.http.write("</table>")
	luci.http.write("</div>")
end
