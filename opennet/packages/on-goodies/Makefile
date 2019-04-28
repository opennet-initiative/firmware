include $(TOPDIR)/rules.mk

PKG_NAME:=on-goodies

include $(INCLUDE_DIR)/opennet.mk

define Package/on-goodies
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=https://www.opennet-initiative.de/
  MAINTAINER:=Opennet Initiative <admin@opennet-initiative.de>
  TITLE:=Useful tools for network and system analysis and development
  DEPENDS:=+bwm-ng +iperf +less +mtr +screen +tcpdump-mini +iftop
endef

define Package/on-goodies/description
	Useful tools for network and system analysis and development
endef

# dummy fuer den openwrt-Buildprozess
define Package/on-goodies/compile
endef

define Package/on-goodies/install
	# dieses Template wird via patches/makefile_include_opennet_packages.patch definiert
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
