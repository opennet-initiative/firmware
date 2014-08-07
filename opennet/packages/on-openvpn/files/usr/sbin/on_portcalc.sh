#!/bin/sh

. "${IPKG_INSTROOT:-}/usr/bin/on-helper.sh"

client_cn=$(get_client_cn)

## calculate forwarded ports
ports=10;
if [ -n "$(expr $client_cn : '\(\(1\.\)\?[0-9][0-9]\?[0-9]\?\.aps\.on\)')" ]; then
	portbase=10000;
	cn_address=${client_cn%.aps.on};
	cn_address=${cn_address#*.};
elif [ -n "$(expr $client_cn : '\([0-9][0-9]\?[0-9]\?\.mobile\.on\)')" ]; then
	portbase=12550;
	cn_address=${client_cn%.mobile.on};
elif [ -n "$(expr $client_cn : '\(2[\._-][0-9][0-9]\?[0-9]\?\.aps\.on\)')" ]; then
	portbase=15100;
	cn_address=${client_cn%.aps.on};
	cn_address=${cn_address#*.};
else
# 	echo "something is wrong with your certificate Common Name";
	exit;
fi
if [ -z "$cn_address" ] || [ $cn_address -lt 1 ] || [ $cn_address -gt 255 ]; then
# 	echo "something is wrong with your certificate Common Name / IP Address";
	exit;
fi
targetports=$((portbase + (cn_address-1)*ports));
echo    "$client_cn $targetports $((targetports+9))"
