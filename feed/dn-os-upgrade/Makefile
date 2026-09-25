include $(TOPDIR)/rules.mk

# DockNeighbor OS's own upgrades. dn-os-upgrade is level 2: the whole image, from the signed release channel,
# keeping settings. dn-pkg-upgrade is level 1 for the dn-* packages: the signed dn_os feed, whose key and feed line
# this package installs. (The hub-lite's own level 1 is its self_update, from DockNeighbor-Hub's feed.)
PKG_NAME:=dn-os-upgrade
PKG_VERSION:=1.1.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=SC4 Technologies

include $(INCLUDE_DIR)/package.mk

define Package/dn-os-upgrade
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=DockNeighbor OS upgrades: full firmware (level 2) and dn-* packages (level 1)
  DEPENDS:=+usign +jsonfilter +jshn +uclient-fetch
  PKGARCH:=all
endef

define Build/Compile
endef

define Package/dn-os-upgrade/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/dn/os-keys $(1)/lib/upgrade/keep.d $(1)/etc/opkg/keys $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/usr/sbin/dn-os-upgrade ./files/usr/sbin/dn-pkg-upgrade $(1)/usr/sbin/
	$(INSTALL_DATA) ./files/etc/opkg/keys/1c44072d07e3e228 $(1)/etc/opkg/keys/
	$(INSTALL_BIN) ./files/etc/uci-defaults/94-dn-os-feed $(1)/etc/uci-defaults/
	$(INSTALL_DATA) ./files/etc/dn/os-keys/* $(1)/etc/dn/os-keys/
	$(INSTALL_DATA) ./files/lib/upgrade/keep.d/dn-os-upgrade $(1)/lib/upgrade/keep.d/
endef

$(eval $(call BuildPackage,dn-os-upgrade))
