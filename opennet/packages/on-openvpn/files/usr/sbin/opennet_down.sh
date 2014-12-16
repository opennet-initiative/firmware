#!/bin/sh
#
# Opennet Firmware
# 
# Copyright 2010 Rene Ejury <opennet@absorb.it>
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
# 	http://www.apache.org/licenses/LICENSE-2.0
# 

rm -f /tmp/openvpn_msg.txt	# remove running message
if [ -f "/etc/init.d/dhcp-fwd" ]; then
	. /etc/init.d/dhcp-fwd
	stop &
fi

# ist die Verbindung via ping-restart abgerissen?
if [ "${signal:-}" = "ping-restart" ]; then
	# markiere die aktuelle Verbindung als kaputt
	broken_service=$(on-function get_active_mig_connections | head -1)
	[ -n "$broken_service" ] && on-function set_service_value "$broken_service" "status" "n" || true
fi

exit 0

