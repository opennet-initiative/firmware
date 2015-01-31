#!/bin/sh

if [  -z $1 ]; then
   echo "Bad parameter! IP as parameter is needed."
   echo "e.g."
   echo "      traceroute-oni.sh 192.168.0.33"
   echo
   exit
fi

source oni_tracert_mtr_helper.sh $1 method-traceroute