include $(TOPDIR)/rules.mk

PKG_NAME:=on-wifidog

include $(INCLUDE_DIR)/opennet.mk

define Package/on-wifidog
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Rene Ejury <opennet@absorb.it>
  TITLE:=Wifidog extensions
  DEPENDS+=+on-core +on-openvpn +dhcp-forwarder +wifidog
endef

define Package/on-wifidog/description
	Opennet-specific implementation for a public hotspot.
endef

define Package/on-wifidog/install
	# this template  is defined in ../../../openwrt/include/opennet.mk ( uses luci localisation)
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

