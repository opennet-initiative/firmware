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

# dummy fuer den openwrt-Buildprozess
define Package/on-tinc/compile
endef

define Package/on-tinc/install
	# dieses Template wird via patches/makefile_include_opennet_packages.patch definiert
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
