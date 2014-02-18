# Opennet-Integration into OpenWrt
# copied from luci (luci.subsignal.org) and adapted for Opennet-Software

include $(TOPDIR)/rules.mk

PKG_BRANCH:=trunk

ifeq ($(DUMP),)
#  USELOCAL:=$(shell grep luci ../../../.project 2>/dev/null >/dev/null && echo 1)
# currently only use local, change if online-repository is available
   USELOCAL:=1
endif

PKG_NAME:=opennet
PKG_RELEASE:=5

ifeq ($(USELOCAL),1)
  PKG_VERSION:=0.4
else
  PKG_SOURCE_URL:=http://git.opennet-initiative.de/opennet/$(PKG_BRANCH)
  ifeq ($(DUMP),)
    PKG_REV:=$(shell LC_ALL=C svn info $(CURDIR) | sed -ne's/^Revision: //p')
    PKG_VERSION:=0.4$(PKG_REV)
  endif
  PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
  PKG_SOURCE:=$(PKG_SOURCE_SUBDIR).tar.gz
  PKG_SOURCE_PROTO:=git
  PKG_SOURCE_VERSION:=$(PKG_REV)
endif

PKG_BUILD_DEPENDS:=$(if $(STAGING_DIR_ROOT),lua/host)
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_INSTALL_DIR:=$(PKG_BUILD_DIR)/ipkg-install

LUA_TARGET:=source
LUCI_CFLAGS:=
PKG_SELECTED_MODULES:=

ifeq ($(BOARD),brcm-2.4)
  MAKE_FLAGS += CRAP="1"
endif


include $(INCLUDE_DIR)/package.mk

ifeq ($(USELOCAL),1)
  define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) c -C ../../../ . \
		--exclude=.pc --exclude=.svn --exclude=.git \
		--exclude='boa-0*' --exclude='*.o' --exclude='*.so' \
		--exclude=dist | \
			tar x -C $(PKG_BUILD_DIR)/
  endef
endif

define Build/Configure
endef

### Templates ###

define Package/on-core/config
       choice
               prompt "Build Target"
               default PACKAGE_on-core_source

       config PACKAGE_on-core_compile
               bool "Precompiled"

       config PACKAGE_on-core_stripped
               bool "Stripped"

       config PACKAGE_on-core_srcdiet
               bool "Compressed Source"

       config PACKAGE_on-core_source
               bool "Full Source"

       endchoice
endef

ifneq ($(CONFIG_PACKAGE_on-core_compile),)
  LUA_TARGET:=compile
endif

ifneq ($(CONFIG_PACKAGE_on-core_stripped),)
  LUA_TARGET:=strip
endif

ifneq ($(CONFIG_PACKAGE_on-core_srcdiet),)
  LUA_TARGET:=diet
endif

### Applications ###

MAKE_FLAGS += \
	MODULES="$(PKG_SELECTED_MODULES)" \
	LUA_TARGET="$(LUA_TARGET)" \
	LUA_SHLIBS="-llua -lm -ldl -lcrypt" \
	CFLAGS="$(TARGET_CFLAGS) $(LUCI_CFLAGS) -I$(STAGING_DIR)/usr/include" \
	LDFLAGS="$(TARGET_LDFLAGS) -L$(STAGING_DIR)/usr/lib" \
	NIXIO_TLS="$(NIXIO_TLS)" OS="Linux"

