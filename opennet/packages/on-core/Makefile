include $(TOPDIR)/rules.mk

PKG_NAME:=on-core

include $(INCLUDE_DIR)/opennet.mk

define Package/on-core
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=https://www.opennet-initiative.de/
  MAINTAINER:=Opennet Initiative <admin@opennet-initiative.de>
  TITLE:=System and Webinterface
  DEPENDS+=+on-certificates +olsrd +olsrd-mod-httpinfo +olsrd-mod-txtinfo +olsrd-mod-nameservice +olsrd-mod-jsoninfo +ip +coreutils +coreutils-timeout
endef

define Package/on-core/description
	Basic opennet-specific settings
endef

# dummy fuer den openwrt-Buildprozess
define Package/on-core/compile
endef

define Package/on-core/install
	# dieses Template wird via patches/makefile_include_opennet_packages.patch definiert
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

define Package/on-core/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
on-function on_opkg_postinst_default
on-function apply_changes "$(PKG_NAME)"
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
