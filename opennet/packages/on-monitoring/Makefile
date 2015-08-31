include $(TOPDIR)/rules.mk

PKG_NAME:=on-monitoring

include $(INCLUDE_DIR)/opennet.mk

define Package/on-monitoring
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Opennet Initiative <admin@opennet-initiative.de>
  TITLE:=Monitoring of Opennet services and network properties
  DEPENDS:=+muninlite
endef

define Package/on-monitoring/description
	Monitoring for Opennet Access Points. The published data may compromise privacy by exposing traffic patterns.
endef

# dummy fuer den openwrt-Buildprozess
define Package/on-monitoring/compile
endef

define Package/on-monitoring/install
	# dieses Template wird via patches/makefile_include_opennet_packages.patch definiert
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

