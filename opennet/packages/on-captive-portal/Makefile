include $(TOPDIR)/rules.mk

PKG_NAME:=on-captive-portal

include $(INCLUDE_DIR)/opennet.mk

define Package/on-captive-portal
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Philipp Markwardt <philipp.markwardt@on-i.de>
  TITLE:=Captive Portal Extension
  # wir benoetigen mehr als 0.9_beta9.8 - sort gibt es keine uci-Konfiguration
  DEPENDS+=+on-openvpn +nodogsplash>=0.9_beta9.9.9
endef

define Package/on-captive-portal/description
	Opennet-specific implementation for a public hotspot.
endef

# dummy fuer den openwrt-Buildprozess
define Package/on-captive-portal/compile
endef

define Package/on-captive-portal/install
	# dieses Template wird via patches/makefile_include_opennet_packages.patch definiert
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

