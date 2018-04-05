#!/bin/sh
#
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
}

if [ "$ACTION" = "ifup" ] || [ "$ACTION" = "ifdown" ]; then
	if on-function is_on_module_installed_and_enabled "on-captive-portal"; then
		process_captive_portal_triggers
	fi
fi
