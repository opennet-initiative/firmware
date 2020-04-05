include $(TOPDIR)/rules.mk

PKG_NAME:=on-openvpn-v6

include $(INCLUDE_DIR)/opennet.mk

define Package/on-openvpn-v6
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=https://www.opennet-initiative.de/
  MAINTAINER:=Opennet Initiative <admin@opennet-initiative.de>
  TITLE:=VPN IPv6 extensions
  DEPENDS+=+on-openvpn +ndppd
endef

define Package/on-openvpn-v6/description
	Opennet-specific additions to OpenVPN IPv6:
endef

# dummy fuer den openwrt-Buildprozess
define Package/on-openvpn-v6/compile
endef

define Package/on-openvpn-v6/install
	# dieses Template wird via patches/makefile_include_opennet_packages.patch definiert
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

define Package/on-openvpn-v6/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
on-function on_opkg_postinst_default
#on-function cleanup_stale_openvpn_services #brauchen wir das für v6?
on-function apply_changes "$(PKG_NAME)"
endef

define Package/on-openvpn-v6/prerm
#!/bin/sh
on-function delete_openvpn_v6_service
on-function delete_tunnel_v6_firewall
on-function delete_tunnel_v6_network
endef

define Package/on-openvpn-v6/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
on-function on_opkg_postrm_default
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
