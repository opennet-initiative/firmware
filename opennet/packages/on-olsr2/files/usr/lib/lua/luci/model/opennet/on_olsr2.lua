module("luci.model.opennet.on_olsr2", package.seeall)

function status_neighbors_olsr2()
	require("luci.model.opennet.funcs")
	luci.http.prepare_content("text/plain")
	local neighbour_info = on_function("get_olsr2_neighbours")
	local response = ""
	if not is_string_empty(neighbour_info) then
		response = response .. '<div class="table"><div class="tr table-titles">' ..
			'<div class="th">' ..  luci.i18n.translate("Name") .. "</div>" ..
			'<div class="th">' ..  luci.i18n.translate("IP-Address") .. "</div>" ..
			'<div class="th">' ..  luci.i18n.translate("Interface") .. "</div>" ..
			'<div class="th"><abbr title="' .. luci.i18n.translate("Potential outgoing rate: estimated by this host") .. '">Announced TX Rate</abbr></div>' ..
			'<div class="th"><abbr title="' .. luci.i18n.translate("Potential incoming rate: estimated by our neighbour") .. '">Received RX Rate</abbr></div>' ..
			'<div class="th"><abbr title="' .. luci.i18n.translate("Number of routes via this neighbour") .. '">Routes</abbr></div>' ..
			'</div>'
		for _, line in pairs(line_split(neighbour_info)) do
			local info = space_split(line)
			-- keine Ausgabe, falls nicht mindestens fuenf Felder geparsed wurden
			-- (die Ursache fuer weniger als fuenf Felder ist unklar - aber es kam schon vor)
			if info[6] then
				response = response .. '<div class="tr">' ..
					'<div class="td"><a href="http://' .. info[1] .. '/">' .. info[1] .. '</a></div>' ..
					'<div class="td">' .. info[2] .. '</div>' ..
					'<div class="td">' .. info[3] .. '</div>' ..
					'<div class="td">' .. info[4] .. '</div>' ..
					'<div class="td">' .. info[5] .. '</div>' ..
					'<div class="td right">' .. info[6] .. '</div>' ..
					'</div>'
			end
		end
		response = response .. '</div>'
	else
		response = response .. '<div class="alert-message">' ..
			luci.i18n.translate("Currently there are no known routing neighbours.") .. " " ..
			luci.i18n.translatef('Maybe you want to connect to a local <a href="%s">wifi peer</a>.',
				get_wifi_setup_link()) ..
			'</div>'
	end
	luci.http.write(response)
end
