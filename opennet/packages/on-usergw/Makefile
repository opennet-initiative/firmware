include $(TOPDIR)/rules.mk

PKG_NAME:=on-usergw

include $(INCLUDE_DIR)/opennet.mk

define Package/on-usergw
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Opennet Initiative <admin@opennet-initiative.de>
  TITLE:=Usergateway extensions
  DEPENDS+=+on-core +openvpn-openssl +openssl-util +curl +ifstat +drill
endef

define Package/on-usergw/description
	Opennet-specific additions necessary for sharing an uplink with the mesh.
endef

# dummy fuer den openwrt-Buildprozess
define Package/on-usergw/compile
endef

define Package/on-usergw/install
	# dieses Template wird via patches/makefile_include_opennet_packages.patch definiert
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

