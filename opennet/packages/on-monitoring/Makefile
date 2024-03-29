include $(TOPDIR)/rules.mk

PKG_NAME:=on-monitoring

include $(INCLUDE_DIR)/opennet.mk

define Package/on-monitoring
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=https://www.opennet-initiative.de/
  MAINTAINER:=Opennet Initiative <admin@opennet-initiative.de>
  TITLE:=Monitoring of Opennet services and network properties
  DEPENDS:=+on-core +muninlite +micropython
endef

define Package/on-monitoring/description
	Monitoring for Opennet Access Points. The published data may compromise privacy by exposing traffic patterns.
endef

# dummy fuer den openwrt-Buildprozess
define Package/on-monitoring/compile
endef

define Package/on-monitoring/install
	# dieses Template wird via patches/makefile_include_opennet_packages.patch definiert
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

define Package/on-monitoring/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0

# zuerst die Caches zuruecksetzen
# erst nach der Cache-Loeschung sind die neuen Funktionen verfuegbar
/usr/bin/on-function on_opkg_postinst_default

on-function schedule_task <<-EOF
	# Leider, leider ist muninlite noch nicht installiert, wenn diese Funktion aufgerufen wird.
	# Daher warten wir einfach ein wenig und hoffen, dass es zwischendurch keinen Neustart gibt.
	sleep 20

	# automatisch konfigurierte munin-Plugins verlinken
	on-function enable_suggested_munin_plugin_names "wireless_channel_active_"
	on-function enable_suggested_munin_plugin_names "wireless_channel_occupation_"
	on-function enable_suggested_munin_plugin_names "wireless_signal_ranges_"

	# Die Komponenten "traffic" und "events" des ath9k-Plugins offenbaren Verkehrsmuster von
	# individuellen Nachbarn - wir aktivieren also nur die unverfänglichen "rcstats".
	# Wobei wir auf eine Aktivierung verzichten, falls es kein wifi-Interface gibt. Dies
	# können wir an der leeren Ausgabe von "suggest" erkennen.
	[ -n "$(/usr/share/munin-plugins-available/ath9k_ suggest)" ] && \
		ln -sfn ../../share/munin-plugins-available/ath9k_ /usr/sbin/munin-node-plugin.d/

	# Das "wireless_signal_noise_"-Plugin offenbart MAC-Addressn - dies soll nicht auf einem
	# offenen Zugangspunkt geschehen.
	on-function is_on_module_installed_and_enabled on-captive-portal || \
		on-function enable_suggested_munin_plugin_names "wireless_signal_noise_"

	on-function is_on_module_installed_and_enabled on-olsr2 && \
		ln -sfn ../../share/munin-plugins-available/olsr2 /usr/sbin/munin-node-plugin.d/

	# Patch auf /usr/sbin/munin-node anwenden, um die Verwendung von Modulen zu ermöglichen
	on-function enable_munin_plugins
EOF

on-function apply_changes "$(PKG_NAME)"
endef

define Package/on-monitoring/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
# wir nehmen an, dass munin abgeschaltet werden soll, wenn der Nutzer das "on-monitoring"-Paket entfernt
on-function disable_monitoring

# automatisch konfigurierte munin-Plugins entfernen
on-function remove_suggested_munin_plugin_names "wireless_channel_occupation_"
endef

define Package/on-monitoring/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
on-function on_opkg_postrm_default
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
