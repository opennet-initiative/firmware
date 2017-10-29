# formatting details: see "get_olsr_service"

BEGIN { OFS = "\t"; }
{
	# example input:
	#   openvpn://192.168.2.191:5101|udp|gw public_host:subaru.opennet-initiative.de upload:293 download:11786   #192.168.2.191
	if ($1 && ($1 ~ /^[^#]/)) {
		# remove trailing " #..." (describing the source of the announcement)
		sub("[[:blank:]]+#.*$", "", $0);

		split($0, tokens, "|");

		# parse the first part, e.g. "openvpn://192.168.2.191:5101"
		split(tokens[1], url_tokens, ":");
		scheme = url_tokens[1];
		host = substr(url_tokens[2], 3);
		split(url_tokens[3], port_and_path, "/");
		port = port_and_path[1];
		path = "/" port_and_path[2];

		protocol = tokens[2];
		details_count = split(tokens[3], service_and_details) - 1;
		service = service_and_details[1];
		if (details_count > 0) {
			details = tokens[3];
			sub("^[^ ]+ ", "", details);
		} else {
			details = "";
		}

		if ((scheme == "http") && (port == "8080") && (protocol == "tcp") && ((service == "gw") || (service == "ugw"))) {
			scheme = "openvpn";
			port = "1600";
			protocol = "udp";
			service = "gw";
		}
		print(service, scheme, host, port, protocol, path, details);
	}
}
