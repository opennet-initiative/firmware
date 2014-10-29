#!/bin/sh
#
# Opennet Firmware
#
# Copyright 2010 Rene Ejury <opennet@absorb.it>
# Copyright 2014 Lars Kruse <devel@sumpfralle.de>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#

# if UGW-HNA announced in olsrd is not used for more than one week,
# HNA will be set free (in olsrd-config and on-usergw-config)

. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"

maxage=604800	# max HNA age is one week (in seconds)
now=$(date +%s)

find_all_uci_sections olsrd Hna4 "source=ugw" | while read uci_prefix; do
	lastused=$(uci_get olsrd.@Hna4[${no}].lastused)
	if [ -z "$lastused" ] || [ "$lastused" -lt "$((now-maxage))" ]; then
		uci_delete "$uci_prefix"
		apply_changes olsrd
		uci del on-usergw.ugwng_hna
		uci commit on-usergw
	fi
done

