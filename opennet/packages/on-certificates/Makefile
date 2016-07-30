include $(TOPDIR)/rules.mk

PKG_NAME:=on-certificates

include $(INCLUDE_DIR)/opennet.mk

define Package/on-certificates
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Opennet Initiative <admin@opennet-initiative.de>
  TITLE:=CA Certificates for OpenVPN and http clients
  DEPENDS:=+curl +openssl-util
endef

define Package/on-certificates/description
	Opennet CA certificates
endef

# dummy fuer den openwrt-Buildprozess
define Package/on-certificates/compile
endef

define Package/on-certificates/install
	# dieses Template wird via patches/makefile_include_opennet_packages.patch definiert
	$(call Package/opennet/install/template,$(1),$(PKG_NAME))
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
