include $(TOPDIR)/rules.mk

PKG_NAME:=on-openvpn

include $(INCLUDE_DIR)/opennet.mk

define Package/on-openvpn
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=https://www.opennet-initiative.de/
  MAINTAINER:=Opennet Initiative <admin@opennet-initiative.de>
  TITLE:=VPN extensions
  # iptables-mod-ipopt ist fuer das iptables-Modul "tos" erforderlich
  DEPENDS+=+on-core +on-certificates +openvpn-openssl +iptables-mod-ipopt +@OPENVPN_openssl_ENABLE_LZO
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

define Package/on-openvpn/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
on-function on_opkg_postinst_default
on-function cleanup_stale_openvpn_services
on-function apply_changes "$(PKG_NAME)"
endef

define Package/on-openvpn/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
# multiping-Hosts aus Monitoring entfernen (siehe updown-Ereignis-Skript)
on-function is_package_installed "on-monitoring" && {
	on-function del_monitoring_multiping_host_by_label "gateway"
	on-function del_monitoring_multiping_host_by_label "ugw"
}
on-function on_opkg_postrm_default
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
