include $(TOPDIR)/rules.mk

PKG_NAME:=on-core

include $(INCLUDE_DIR)/opennet.mk

define Package/on-core
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Rene Ejury <opennet@absorb.it>
  TITLE:=System and Webinterface
  DEPENDS+=+luci-mod-admin-core +olsrd +olsrd-mod-httpinfo +olsrd-mod-txtinfo +olsrd-mod-nameservice +luci-app-firewall +ntpclient
endef

define Package/on-core/description
	Basic opennet-specific settings
endef

define Package/on-core/install
	# this template  is defined in ../../../openwrt/include/opennet.mk ( uses luci localisation)
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

