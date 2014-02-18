#!/bin/sh
if [ -z "$(pidof olsrd)" ]; then
    /etc/init.d/olsrd start
    if [ -n "$(pidof olsrd)" ]; then
        echo " - $(date) - olsrd restart  -----" >>/etc/banner; sync
    fi
fi
