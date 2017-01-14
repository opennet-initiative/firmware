include $(TOPDIR)/rules.mk

PKG_NAME:=on-captive-portal

include $(INCLUDE_DIR)/opennet.mk

define Package/on-captive-portal
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Philipp Markwardt <philipp.markwardt@on-i.de>
  TITLE:=Captive Portal Extension
  DEPENDS+=+on-openvpn +nodogsplash
endef

define Package/on-captive-portal/description
	Opennet-specific implementation for a public hotspot.
endef

# dummy fuer den openwrt-Buildprozess
define Package/on-captive-portal/compile
endef

define Package/on-captive-portal/install
	# dieses Template wird via patches/makefile_include_opennet_packages.patch definiert
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

define Package/on-captive-portal/postinst
#!/bin/sh
[ "$${IPKG_NO_SCRIPT:-}" = "1" ] && exit 0
# Das munin-Plugin "wireless_signal_noise_" offenbart die MAC-Adressen von captive-Portal-Clients.
# Dies wollen wir nicht.
on-function is_on_module_installed_and_enabled on-captive-portal && \
	on-function disable_munin_plugin "wireless_signal_noise_"
on-function on_opkg_postinst_default
on-function apply_changes "$(PKG_NAME)"
endef

define Package/on-captive-portal/prerm
#!/bin/sh
[ "$${IPKG_NO_SCRIPT:-}" = "1" ] && exit 0
on-function disable_captive_portal
endef

define Package/on-captive-portal/postrm
#!/bin/sh
[ "$${IPKG_NO_SCRIPT:-}" = "1" ] && exit 0
on-function on_opkg_postrm_default
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
