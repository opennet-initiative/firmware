include $(TOPDIR)/rules.mk

PKG_NAME:=on-usergw
PKG_VERSION:=$(shell cat ../../VERSION)
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_BUILD_DEPENDS:=$(if $(STAGING_DIR_ROOT),lua/host)

include $(INCLUDE_DIR)/package.mk


define Package/on-usergw
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Rene Ejury <opennet@absorb.it>
  TITLE:=Usergateway extensions
  DEPENDS+=+on-core +on-openvpn +ifstat
endef

define Package/on-usergw/description
	Opennet-specific additions necessary for sharing an uplink with the mesh.
endef

define Package/on-usergw/install
	$(CP) -a $(PKG_BUILD_DIR)/$(2)/dist/* $(1)/ -R
	$(CP) -a $(PKG_BUILD_DIR)/$(2)/ipkg/* $(1)/CONTROL/ 2>/dev/null || true
endef

$(eval $(call BuildPackage,on-usergw))

