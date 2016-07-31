function status_neighbors_olsr2()
	luci.http.prepare_content("text/plain")
	local neighbour_info = on_function("get_olsr2_neighbours")
	local response = ""
	if not is_string_empty(neighbour_info) then
		response = response .. '<table class="status_page_table"><tr>' ..
			'<th>' ..  luci.i18n.translate("Name") .. "</th>" ..
			'<th>' ..  luci.i18n.translate("IP-Address") .. "</th>" ..
			'<th>' ..  luci.i18n.translate("Interface") .. "</th>" ..
			'<th><abbr title="' .. luci.i18n.translate("Potential outgoing rate: estimated by this host") .. '">Announced RX Rate</abbr></th>' ..
			'<th><abbr title="' .. luci.i18n.translate("Potential incoming rate: estimated by our neighbour") .. '">Received RX Rate</abbr></th>' ..
			'<th><abbr title="' .. luci.i18n.translate("Number of routes via this neighbour") .. '">Routes</abbr></th>' ..
			'</tr>'
		for _, line in pairs(line_split(neighbour_info)) do
			local info = space_split(line)
			-- keine Ausgabe, falls nicht mindestens fuenf Felder geparsed wurden
			-- (die Ursache fuer weniger als fuenf Felder ist unklar - aber es kam schon vor)
			if info[6] then
				response = response .. '<tr>' ..
					'<td><a href="http://' .. info[1] .. '/">' .. info[1] .. '</a></td>' ..
					'<td>' .. info[2] .. '</td>' ..
					'<td>' .. info[3] .. '</td>' ..
					'<td>' .. info[4] .. '</td>' ..
					'<td>' .. info[5] .. '</td>' ..
					'<td style="text-align:right">' .. info[6] .. '</td>' ..
					'</tr>'
			end
		end
		response = response .. '</table>'
	else
		response = response .. '<div class="errorbox">' ..
			luci.i18n.translate("Currently there are no known routing neighbours.") .. " " ..
			luci.i18n.translatef('Maybe you want to connect to a local <a href="%s">wifi peer</a>.',
				luci.dispatcher.build_url("admin", "network", "wireless")) ..
			'</div>'
	end
	luci.http.write(response)
end
