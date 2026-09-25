include $(TOPDIR)/rules.mk

# The level-2 upgrade: the whole DockNeighbor OS image, from the signed release channel, keeping settings.
# (Level 1, the hub-lite package alone, is opkg from DockNeighbor-Hub's signed feed.)
PKG_NAME:=dn-os-upgrade
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=SC4 Technologies

include $(INCLUDE_DIR)/package.mk

define Package/dn-os-upgrade
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=DockNeighbor OS full-firmware upgrade (signed channel)
  DEPENDS:=+usign +jsonfilter +jshn +uclient-fetch
  PKGARCH:=all
endef

define Build/Compile
endef

define Package/dn-os-upgrade/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/dn/os-keys $(1)/lib/upgrade/keep.d
	$(INSTALL_BIN) ./files/usr/sbin/dn-os-upgrade $(1)/usr/sbin/
	$(INSTALL_DATA) ./files/etc/dn/os-keys/* $(1)/etc/dn/os-keys/
	$(INSTALL_DATA) ./files/lib/upgrade/keep.d/dn-os-upgrade $(1)/lib/upgrade/keep.d/
endef

$(eval $(call BuildPackage,dn-os-upgrade))
