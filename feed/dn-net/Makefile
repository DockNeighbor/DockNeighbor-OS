include $(TOPDIR)/rules.mk

# The DN device API's OS half: the router's network settings as JSON (dn-net <verb>), in the app's
# NetworkDeviceDriver shapes, behind the hub-lite's /api/hub/net/* door. Also the ONE implementation of the Wi-Fi
# uplink's role -> firewall rule (/usr/lib/dn-net/uplink.sh), which dn-handoff uses too.
PKG_NAME:=dn-net
PKG_VERSION:=1.3.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=SC4 Technologies

include $(INCLUDE_DIR)/package.mk

define Package/dn-net
  SECTION:=net
  CATEGORY:=Network
  TITLE:=DockNeighbor OS network settings as JSON (the DN device API)
  DEPENDS:=+jshn +jsonfilter +iwinfo +dn-auth
  PKGARCH:=all
endef

define Package/dn-net/conffiles
/etc/config/dn-net
endef

define Build/Compile
endef

define Package/dn-net/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/usr/lib/dn-net $(1)/usr/libexec/dn-net $(1)/etc/config $(1)/etc/sysctl.d
	$(INSTALL_BIN) ./files/usr/sbin/dn-net $(1)/usr/sbin/
	$(INSTALL_BIN) ./files/usr/libexec/dn-net/mode-watch $(1)/usr/libexec/dn-net/
	$(INSTALL_DATA) ./files/etc/sysctl.d/90-dn-net.conf $(1)/etc/sysctl.d/
	$(INSTALL_DATA) ./files/usr/lib/dn-net/uplink.sh $(1)/usr/lib/dn-net/
	$(INSTALL_CONF) ./files/etc/config/dn-net $(1)/etc/config/
endef

$(eval $(call BuildPackage,dn-net))
