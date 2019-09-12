#!/bin/sh
#
# Konfiguriere uebliche Opennet-Interfaces sowie ein lokales Interface.
#
# Dieses Skript wird nur ein einziges Mal nach einem Upgrade oder der Erstinstallation ausgefuehrt:
#   http://wiki.openwrt.org/doc/uci#defaults
#
# Wir brauchen dieses Skript nur, weil derzeit die wireless Datei falsch von OpenWRT generiert wird.
# Sobald dies korrigiert ist, können wir dies hier löschen.
# Prüfe die wireless.orig, um zu sehen, wie die Originaldatei aussieht.
#

model_name=$(jsonfilter -i /etc/board.json -e '@.model.name')

if [ "$model_name" = "Ubiquiti Nanostation AC loco (WA)" ]; then

  #backup orig wireless
  mv /etc/config/wireless /etc/config/wireless.orig

  #write new wireless file
  cat >>/etc/config/wireless <<EOF
config wifi-device 'radio0'
	option type 'mac80211'
	option country 'DE'
	option hwmode '11a'
	option path 'pci0000:00/0000:00:00.0'
	option htmode 'HT40'
	option channel '104'
	option chanlist '44 100-116 136'

config wifi-iface 'default_radio0'
	option device 'radio0'
	option mode 'ap'
	option encryption 'none'
	option network 'on_wifi_0'
	option ifname 'wlan0'
	option ssid 'apname.on-i.de'
	option isolate '1'

config wifi-device 'radio1'
	option type 'mac80211'
	option hwmode '11g'
	option path 'platform/ahb/ahb:apb/18100000.wmac'
	option htmode 'HT20'
	option country 'DE'
	option channel '1'

config wifi-iface 'default_radio1'
	option device 'radio1'
	option encryption 'none'
	option network 'on_wifi_1'
	option ifname 'wlan1'
	option ssid 'olsr.opennet-initiative.de'
	option mode 'adhoc'
	option bssid '02:ca:ff:ee:ba:be'
	option disabled '1'
EOF

fi

