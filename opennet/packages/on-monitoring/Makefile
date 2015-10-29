include $(TOPDIR)/rules.mk

PKG_NAME:=on-monitoring

include $(INCLUDE_DIR)/opennet.mk

define Package/on-monitoring
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Opennet Initiative <admin@opennet-initiative.de>
  TITLE:=Monitoring of Opennet services and network properties
  DEPENDS:=+muninlite +micropython +micropython-lib
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
[ "$${IPKG_NO_SCRIPT:-}" = "1" ] && exit 0

# zuerst die Caches zuruecksetzen
# erst nach der Cache-Loeschung sind die neuen Funktionen verfuegbar
on-function on_opkg_postinst_default

# automatisch konfigurierte munin-Plugins verlinken
on-function enable_suggested_munin_plugin_names "wireless_channel_occupation_"

on-function schedule_task <<-EOF
	# Leider, leider ist muninlite noch nicht installiert, wenn diese Funktion aufgerufen wird.
	# Daher warten wir einfach ein wenig und hoffen, dass es zwischendurch keinen Neustart gibt.
	sleep 20

	# Patch auf /usr/sbin/munin-node anwenden, um die Verwendung von Modulen zu ermöglichen
	on-function enable_munin_plugins

	# munin starten oder stoppen (je nach Modul-Aktivierung)
	on-function update_monitoring_state
EOF
endef

define Package/on-monitoring/prerm
#!/bin/sh
[ "$${IPKG_NO_SCRIPT:-}" = "1" ] && exit 0
# wir nehmen an, dass munin abgeschaltet werden soll, wenn der Nutzer das "on-monitoring"-Paket entfernt
on-function disable_monitoring

# automatisch konfigurierte munin-Plugins entfernen
on-function remove_suggested_munin_plugin_names "wireless_channel_occupation_"
endef

define Package/on-monitoring/postrm
#!/bin/sh
[ "$${IPKG_NO_SCRIPT:-}" = "1" ] && exit 0
on-function on_opkg_postrm_default
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

