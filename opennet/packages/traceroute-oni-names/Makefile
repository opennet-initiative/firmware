include $(TOPDIR)/rules.mk

PKG_NAME:=traceroute-oni-names
PKG_VERSION:=0.9
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/traceroute-oni-names
  SECTION:=opennet
  CATEGORY:=Opennet
  URL:=http://www.opennet-initiative.de/
  MAINTAINER:=Martin Garbe <monomartin@on-i.de>
  TITLE:=Traceroute with Opennet names
  DEPENDS:=+mtr
endef

define Package/traceroute-oni-names/description
	Opennet-specific traceroute and mtr output including location information to each IP
endef

# falls Build/Compile nicht definiert wird, dann wird das Makefile aus dem build_dir geloescht
# siehe https://forum.openwrt.org/viewtopic.php?pid=143534#p143534
define Build/Compile
endef

# dummy fuer den openwrt-Buildprozess
define Package/traceroute-oni-names/compile
endef

define Package/traceroute-oni-names/install
	$(CP) -a -R "./files/." "$(1)/"
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

