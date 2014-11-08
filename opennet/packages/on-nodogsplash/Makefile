include $(TOPDIR)/rules.mk

PKG_NAME:=on-nodogsplash

include $(INCLUDE_DIR)/opennet.mk

define Package/on-nodogsplash
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Philipp Markwardt <philipp.markwardt@on-i.de>
  TITLE:=Nodogsplash extension
  DEPENDS+=+on-core +nodogsplash
endef

define Package/on-nodogsplash/description
	Opennet-specific implementation for a public hotspot.
endef

define Package/on-nodogsplash/install
	# this template  is defined in ../../../openwrt/include/opennet.mk ( uses luci localisation)
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

define Package/on-nodogsplash/postinst
# # check if we are on real system
if [ -z "${IPKG_INSTROOT:-}" ]; then
        echo "*** opennet-nodogsplash-package was installed *****"
        echo "restart your system after installation finished"
        echo "bitte nach Ende der Installation neu starten"
        echo "***********************************************"
    /etc/init.d/on_nodogsplash_config enable

    #replace nodogsplash configs with ONI settings
    /etc/uci-defaults/on-captive-nodogsplash
    #delete file because it is only used once
    rm /etc/uci-defaults/on-captive-nodogsplash
    exit 0
fi
endef

define Package/on-nodogsplash/postrm
# # check if we are on real system
if [ -z "${IPKG_INSTROOT:-}" ]; then
    /etc/init.d/on_nodogsplash_config disable
    exit 0
fi
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

