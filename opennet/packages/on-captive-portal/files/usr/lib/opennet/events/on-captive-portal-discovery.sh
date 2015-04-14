#!/bin/sh
#
# Starte/stoppe den nodogsplash-Dienst je nach Verfügbarkeit des hotspot-Netzwerk-Interface.
# Aktiviere/deaktiviere das hotspot-Netzwerk-Interface je nach Verfügbarkeit des Opennet-VPN-Tunnels.
#


# wir verwenden explizit ein sub-Shell um Seiteneffekte für andere hotplug-Skripte zu vermeiden
process_captive_portal_triggers() {
	. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"

	# das Opennet-VPN-Interface triggert die Aktivierung/Deaktivierung des hotspot-Interface
	if [ "$INTERFACE" = "$NETWORK_TUNNEL" ]; then
		msg_info "Trigger activation of Captive Portal interface following the state of the VPN tunnel"
		if [ "$ACTION" = "ifup" ]; then
			ifup "$NETWORK_FREE"
		elif [ "$ACTION" = "ifdown" ]; then
			ifdown "$NETWORK_FREE"
		fi
	fi


	# das Hotspot-Interface triggert die Aktivierung des nodogsplash-Dienst
	if [ "$INTERFACE" = "$NETWORK_FREE" ]; then
		if [ "$ACTION" = "ifup" -o "$ACTION" = "ifdown" ]; then
			msg_info "Trigger reload of Captive Portal service due to interface status change ($INTERFACE -> $ACTION)"
			# eventuell läuft er schon für andere Zwecke - "reload" sollte immer funktionieren
			/etc/init.d/nodogsplash reload
		fi
	fi
}

process_captive_portal_triggers 2>&1 >/dev/null | logger -t captive-portal-discovery

