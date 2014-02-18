include $(TOPDIR)/rules.mk

PKG_NAME:=on-wifidog
PKG_VERSION:=$(shell cat ../../VERSION)
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_BUILD_DEPENDS:=$(if $(STAGING_DIR_ROOT),lua/host)

include $(INCLUDE_DIR)/package.mk


define Package/on-wifidog
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Rene Ejury <opennet@absorb.it>
  TITLE:=Wifidog extensions
  DEPENDS+=+on-core +on-openvpn +dhcp-forwarder
endef

define Package/on-wifidog/install
	$(call Package/opennet/install/template,$(1),applications/on-wifidog)
endef

define Package/on-wifidog/description
	Opennet-specific implementation for a public hotspot.
endef

define Build/Configure
endef

define Package/on-wifidog/install
	$(CP) -a $(PKG_BUILD_DIR)/$(2)/dist/* $(1)/ -R
	$(CP) -a $(PKG_BUILD_DIR)/$(2)/ipkg/* $(1)/CONTROL/ 2>/dev/null || true
endef

$(eval $(call BuildPackage,on-wifidog))


