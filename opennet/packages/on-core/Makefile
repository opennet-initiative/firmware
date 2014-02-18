include $(TOPDIR)/rules.mk

PKG_NAME:=on-core
PKG_VERSION:=$(shell cat ../../VERSION)
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_BUILD_DEPENDS:=$(if $(STAGING_DIR_ROOT),lua/host)

include $(INCLUDE_DIR)/package.mk


define Package/on-core
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Rene Ejury <opennet@absorb.it>
  TITLE:=System and Webinterface
  DEPENDS+=+luci-mod-admin-core +olsrd +olsrd-mod-httpinfo +olsrd-mod-txtinfo +olsrd-mod-nameservice +luci-app-firewall +ntpclient
endef

define Package/on-core/description
	Basic opennet-specific settings
endef

define Package/on-core/install
	$(CP) -a $(PKG_BUILD_DIR)/$(2)/dist/* $(1)/ -R
	$(CP) -a $(PKG_BUILD_DIR)/$(2)/ipkg/* $(1)/CONTROL/ 2>/dev/null || true
endef

$(eval $(call BuildPackage,on-core))

