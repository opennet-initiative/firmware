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

exit 0

