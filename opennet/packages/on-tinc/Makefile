include $(TOPDIR)/rules.mk

PKG_NAME:=on-tinc

include $(INCLUDE_DIR)/opennet.mk

define Package/on-tinc
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Rene Ejury <opennet@absorb.it>
  TITLE:=Tinc tunneling extensions
  DEPENDS+=+on-core +tinc
endef

define Package/on-tinc/description
	Opennet-specific wrapper for tinc - a mesh VPN.
endef

define Package/on-tinc/install
	# this template  is defined in ../../../openwrt/include/opennet.mk ( uses luci localisation)
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

