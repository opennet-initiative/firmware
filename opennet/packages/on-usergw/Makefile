include $(TOPDIR)/rules.mk

PKG_NAME:=on-usergw

include $(INCLUDE_DIR)/opennet.mk

define Package/on-usergw
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=https://www.opennet-initiative.de/
  MAINTAINER:=Opennet Initiative <admin@opennet-initiative.de>
  TITLE:=Usergateway extensions
  # iptables-mod-ipopt ist fuer das iptables-Modul "tos" erforderlich
  # TODO: micropython ist fuer den Verbindungszaehler auf der Status-Seite erforderlich - wie werden wir dies los?
  DEPENDS+=+on-core +on-certificates +openvpn-openssl +iptables-mod-ipopt +micropython +micropython-lib
endef

define Package/on-usergw/description
	Opennet-specific additions necessary for sharing an uplink with the mesh.
endef

# dummy fuer den openwrt-Buildprozess
define Package/on-usergw/compile
endef

define Package/on-usergw/install
	# dieses Template wird via patches/makefile_include_opennet_packages.patch definiert
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

define Package/on-usergw/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
on-function on_opkg_postinst_default
on-function apply_changes "$(PKG_NAME)"
endef

define Package/on-usergw/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
on-function disable_on_usergw
endef

define Package/on-usergw/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
on-function on_opkg_postrm_default
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
