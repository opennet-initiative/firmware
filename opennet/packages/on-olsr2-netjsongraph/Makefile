include $(TOPDIR)/rules.mk

PKG_NAME:=on-olsr2-netjsongraph

include $(INCLUDE_DIR)/opennet.mk

define Package/on-olsr2-netjsongraph
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Opennet Initiative <dev@opennet-initiative.de>
  TITLE:=OLSRv2-Visualisierung
  DEPENDS+=+on-olsr2
endef

define Package/on-olsr2-netjsongraph/description
	Visualisierung des OLSRv2-Routing im Opennet via Web-Interface
endef

# dummy fuer den openwrt-Buildprozess
define Package/on-olsr2-netjsongraph/compile
endef

define Package/on-olsr2-netjsongraph/install
	# dieses Template wird via patches/makefile_include_opennet_packages.patch definiert
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

define Package/on-olsr2-netjsongraph/postinst
#!/bin/sh
[ "$${IPKG_NO_SCRIPT:-}" = "1" ] && exit 0
on-function on_opkg_postinst_default
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
