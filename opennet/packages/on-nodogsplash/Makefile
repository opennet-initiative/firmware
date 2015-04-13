include $(TOPDIR)/rules.mk

PKG_NAME:=on-nodogsplash

include $(INCLUDE_DIR)/opennet.mk

define Package/on-nodogsplash
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Philipp Markwardt <philipp.markwardt@on-i.de>
  TITLE:=Nodogsplash extension
  DEPENDS+=+on-openvpn +nodogsplash
endef

define Package/on-nodogsplash/description
	Opennet-specific implementation for a public hotspot.
endef

# dummy fuer den openwrt-Buildprozess
define Package/on-nodogsplash/compile
endef

define Package/on-nodogsplash/install
	# dieses Template wird via patches/makefile_include_opennet_packages.patch definiert
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

