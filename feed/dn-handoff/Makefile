include $(TOPDIR)/rules.mk

# Carry a router's site settings across a flash (handoff/README.md). The vendor-side reader writes a
# brand-neutral /etc/dn/site.json into the sysupgrade config tarball; on first boot this package turns
# it into this firmware's own config: LAN address, access point, uplink, LTE modem, reservations, admin password.
PKG_NAME:=dn-handoff
PKG_VERSION:=1.4.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=SC4 Technologies

include $(INCLUDE_DIR)/package.mk

define Package/dn-handoff
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=DockNeighbor site handoff (settings survive a vendor-to-DockNeighbor flash)
  DEPENDS:=+jshn +dn-net
  PKGARCH:=all
endef

define Build/Compile
endef

define Package/dn-handoff/install
	$(INSTALL_DIR) $(1)/usr/libexec/dn-handoff $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/usr/libexec/dn-handoff/apply $(1)/usr/libexec/dn-handoff/
	$(INSTALL_BIN) ./files/etc/uci-defaults/05-dn-handoff $(1)/etc/uci-defaults/
endef

$(eval $(call BuildPackage,dn-handoff))
