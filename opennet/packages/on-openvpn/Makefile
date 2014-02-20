include $(TOPDIR)/rules.mk

PKG_NAME:=on-openvpn

include $(INCLUDE_DIR)/opennet.mk

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
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

