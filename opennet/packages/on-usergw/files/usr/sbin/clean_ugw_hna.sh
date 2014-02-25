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
#   http://www.apache.org/licenses/LICENSE-2.0
#

# if UGW-HNA announced in olsrd is not used for more than one week,
# HNA will be set free (in olsrd-config and on-usergw-config)

maxage=604800	# max HNA age is one week (in seconds)
time=$(date +%s)

found=""; no=0;
while ( [ -n "$(uci -q get olsrd.@Hna4[${no}])" ] ); do
	if [ "$(uci -q get olsrd.@Hna4[${no}].source)" == "ugw" ]; then
		lastused=$(uci -q get olsrd.@Hna4[${no}].lastused)
		if [ -z "$lastused" ] || [ $lastused -lt $((time-maxage)) ]; then
			uci del olsrd.@Hna4[${no}]
			uci commit olsrd
			uci del on-usergw.ugwng_hna
			uci commit on-usergw
			/etc/init.d/olsrd restart >/dev/null
		fi
		break	# there should be only one ugw HNA
	fi
done;
