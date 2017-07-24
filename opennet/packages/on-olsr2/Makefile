include $(TOPDIR)/rules.mk

PKG_NAME:=on-olsr2

include $(INCLUDE_DIR)/opennet.mk

define Package/on-olsr2
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Opennet Initiative <dev@opennet-initiative.de>
  TITLE:=OLSRv2-Routing
  DEPENDS+=+on-core +oonf-olsrd2
endef

define Package/on-olsr2/description
	OLSRv2-Routing im Opennet
endef

# dummy fuer den openwrt-Buildprozess
define Package/on-olsr2/compile
endef

define Package/on-olsr2/install
	# dieses Template wird via patches/makefile_include_opennet_packages.patch definiert
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

define Package/on-olsr2/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
on-function on_opkg_postinst_default
on-function apply_changes "$(PKG_NAME)"
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
