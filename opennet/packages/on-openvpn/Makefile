include $(TOPDIR)/rules.mk

PKG_NAME:=on-openvpn
PKG_VERSION:=$(shell cat ../../VERSION)
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_BUILD_DEPENDS:=$(if $(STAGING_DIR_ROOT),lua/host)

include $(INCLUDE_DIR)/package.mk


define Package/on-openvpn
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Rene Ejury <opennet@absorb.it>
  TITLE:=VPN extensions
  DEPENDS+=+on-core +openvpn +libopenssl +openssl-util +liblzo +kmod-tun
endef

define Package/on-openvpn/description
	Opennet-specific additions to OpenVPN:
	- Opennet CA certificate
	- scripts for selecting and detecting uplink VPN gateways
	- web-based private key and CSR generation
endef

define Package/on-openvpn/install
	$(CP) -a $(PKG_BUILD_DIR)/$(2)/dist/* $(1)/ -R
	$(CP) -a $(PKG_BUILD_DIR)/$(2)/ipkg/* $(1)/CONTROL/ 2>/dev/null || true
endef

$(eval $(call BuildPackage,on-openvpn))

