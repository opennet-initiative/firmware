include $(TOPDIR)/rules.mk
PKG_NAME:=on-tinc
PKG_VERSION:=$(shell cat ../../VERSION)
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_BUILD_DEPENDS:=$(if $(STAGING_DIR_ROOT),lua/host)

include $(INCLUDE_DIR)/package.mk


define Package/on-tinc
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Rene Ejury <opennet@absorb.it>
  TITLE:=Tinc tunneling extensions
  DEPENDS+=+on-core +tinc
endef

define Package/on-tinc/install
	$(call Package/opennet/install/template,$(1),applications/on-tinc)
endef

define Package/on-tinc/description
	Opennet-specific wrapper for tinc - a mesh VPN.
endef

define Build/Configure
endef

define Package/on-tinc/install
        $(INSTALL_DIR) $(1)/usr/sbin
        $(INSTALL_BIN) $(PKG_BUILD_DIR)/brctl/brctl $(1)/usr/sbin/
endef

define Package/on-tinc/install
	$(CP) -a $(PKG_BUILD_DIR)/$(2)/dist/* $(1)/ -R
	$(CP) -a $(PKG_BUILD_DIR)/$(2)/ipkg/* $(1)/CONTROL/ 2>/dev/null || true
endef

$(eval $(call BuildPackage,on-tinc))

