include $(TOPDIR)/rules.mk

PKG_NAME:=on-usergw

include $(INCLUDE_DIR)/opennet.mk

define Package/on-usergw
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Rene Ejury <opennet@absorb.it>
  TITLE:=Usergateway extensions
  DEPENDS+=+on-core +on-openvpn +ifstat
endef

define Package/on-usergw/description
	Opennet-specific additions necessary for sharing an uplink with the mesh.
endef

define Package/on-usergw/install
	# this template  is defined in ../../../openwrt/include/opennet.mk ( uses luci localisation)
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

