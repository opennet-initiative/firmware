include $(TOPDIR)/rules.mk

PKG_NAME:=on-openvpn

include $(INCLUDE_DIR)/opennet.mk

define Package/on-openvpn
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Opennet Initiative <admin@opennet-initiative.de>
  TITLE:=VPN extensions
  DEPENDS+=+on-core +((openvpn-openssl && openssl-util) || openvpn-polarssl)
endef

define Package/on-openvpn/description
	Opennet-specific additions to OpenVPN:
	- scripts for selecting and detecting uplink VPN gateways
	- web-based private key and CSR generation
endef

# dummy fuer den openwrt-Buildprozess
define Package/on-openvpn/compile
endef

define Package/on-openvpn/install
	# dieses Template wird via patches/makefile_include_opennet_packages.patch definiert
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

