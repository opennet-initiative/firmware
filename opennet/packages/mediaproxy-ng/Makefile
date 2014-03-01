#
# Copyright (C) 2008-2010 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=mediaproxy-ng
PKG_REV:=f2fc5dc51e7224901c9937d6389a4ac177cb46bf
PKG_VERSION:=20140226
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.bz2
PKG_SOURCE_URL:=git://github.com/sipwise/mediaproxy-ng.git
PKG_SOURCE_PROTO:=git
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE_VERSION:=$(PKG_REV)

PKG_BUILD_DEPENDS:=+pkg_config

#PKG_FIXUP:=autoreconf
#PKG_INSTALL=1

include $(INCLUDE_DIR)/package.mk

define Package/mediaproxy-ng
	SECTION:=net
	CATEGORY:=Network
	SUBMENU:=Telephony
	TITLE:=Mediaproxy NG
	URL:=https://github.com/sipwise/mediaproxy-ng
	MAINTAINER:=Ragnar Nevries <ragnar@nevries.de>
	DEPENDS:=+glib2 +zlib +libopenssl +libpcre +libcurl +xmlrpc-c-client
endef

define Package/mediaproxy-ng/description
     A proxy for RTP traffic and other UDP based media traffic.
endef

#define Build/Configure
#	(cd $(PKG_BUILD_DIR) && $(BASH) -x ./bootstrap)
#	$(call Build/Configure/Default)
#endef

MAKE_PATH=daemon

define Build/Compile
	$(call Build/Compile/Default,all)
endef

#define Build/InstallDev
#	$(INSTALL_DIR) $(1)/usr/include
#	$(INSTALL_DATA) \
#		$(PKG_INSTALL_DIR)/usr/include/ps3*.h \
#		$(1)/usr/include
#
#	$(INSTALL_DIR) $(1)/usr/lib
#	$(INSTALL_BIN) \
#		$(PKG_INSTALL_DIR)/usr/lib/libps3-utils.{la,a,so*} \
#		$(1)/usr/lib/
#endef

define Package/mediaproxy-ng/install
	$(INSTALL_DIR) $(1)/usr/sbin
	#$(INSTALL_DIR) $(1)/usr/bin
	#$(INSTALL_DIR) $(1)/usr/lib

	$(INSTALL_BIN) $(PKG_BUILD_DIR)/daemon/mediaproxy-ng $(1)/usr/sbin
	#$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/sbin/ps3-dump-bootloader $(1)/usr/sbin
	#$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/sbin/ps3-flash-util $(1)/usr/sbin
	#$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/ps3-video-mode $(1)/usr/bin

	#$(CP) $(PKG_INSTALL_DIR)/usr/lib/libps3-utils.so.* $(1)/usr/lib
endef

$(eval $(call BuildPackage,mediaproxy-ng))
