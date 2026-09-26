include $(TOPDIR)/rules.mk

# The hub-lite profile's glue to the OS: points opkg at the Hub's signed feed at first boot, keeps the hub-lite's
# state across a full-OS upgrade, and puts a newer hub-lite back after one. A package (not image files) so a fix
# here reaches routers through the dn_os feed without a new firmware.
PKG_NAME:=dn-hub-lite-os
PKG_VERSION:=1.0.0
PKG_RELEASE:=2
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=SC4 Technologies

include $(INCLUDE_DIR)/package.mk

# No DEPENDS on brvg-hub-lite: it comes from DockNeighbor-Hub's feed, which the SDK can't see. The image installs both.
define Package/dn-hub-lite-os
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=DockNeighbor OS hub-lite profile glue (feed setup, upgrade keep list, restore)
  PKGARCH:=all
endef

define Build/Compile
endef

define Package/dn-hub-lite-os/install
	$(INSTALL_DIR) $(1)/usr/libexec/dn-hub-lite $(1)/etc/init.d $(1)/etc/uci-defaults $(1)/lib/upgrade/keep.d
	$(INSTALL_BIN) ./files/usr/libexec/dn-hub-lite/restore $(1)/usr/libexec/dn-hub-lite/
	$(INSTALL_BIN) ./files/etc/init.d/dn-hub-lite-restore $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/etc/uci-defaults/95-dn-hub-lite $(1)/etc/uci-defaults/
	$(INSTALL_DATA) ./files/lib/upgrade/keep.d/dn-hub-lite $(1)/lib/upgrade/keep.d/
endef

$(eval $(call BuildPackage,dn-hub-lite-os))
