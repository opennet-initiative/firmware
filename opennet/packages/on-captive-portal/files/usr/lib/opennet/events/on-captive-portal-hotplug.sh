#!/bin/sh
#
# Starte/stoppe den nodogsplash-Dienst je nach Verfügbarkeit des hotspot-Netzwerk-Interface.
# Aktiviere/deaktiviere das hotspot-Netzwerk-Interface je nach Verfügbarkeit des Opennet-VPN-Tunnels.
#


# wir verwenden explizit eine sub-Shell um Seiteneffekte für andere hotplug-Skripte zu vermeiden
process_captive_portal_triggers() {
	. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"

	# das Opennet-VPN-Interface triggert die Aktivierung/Deaktivierung des hotspot-Interface
	if [ "$INTERFACE" = "$NETWORK_TUNNEL" ]; then
		msg_info "Trigger activation of Captive Portal interface following the state of the VPN tunnel"
		echo "on-function sync_captive_portal_state_with_mig_connections" | schedule_task
	fi


	# das Hotspot-Interface triggert die Aktivierung des nodogsplash-Dienst
	if [ "$INTERFACE" = "$NETWORK_FREE" ]; then
		msg_info "Trigger reload of Captive Portal service due to interface status change ($INTERFACE -> $ACTION)"
		# eventuell läuft er schon für andere Zwecke - "reload" sollte immer funktionieren
		echo "on-function captive_portal_reload" | schedule_task
		# aus unklarem Grund reagiert dnsmasq nicht selbstaendig auf das neue dhcp-Interface -> sanfter reload
		echo "/etc/init.d/dnsmasq reload" | schedule_task
	fi
}

[ "$ACTION" = "ifup" -o "$ACTION" = "ifdown" ] && process_captive_portal_triggers
true

