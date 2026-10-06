include $(TOPDIR)/rules.mk

# The read-only status page (owner ruling 2026-10-05): the router's radios, its hub and its cloud connection, on :80
# for anyone on the LAN, with no settings and no secrets, and up even with local administration off. Its own uhttpd
# instance, so the system uhttpd stays disabled.
PKG_NAME:=dn-status
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=SC4 Technologies

include $(INCLUDE_DIR)/package.mk

define Package/dn-status
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=DockNeighbor OS status page (radios, hub, cloud; read-only)
  DEPENDS:=+uhttpd +jshn +jsonfilter
  PKGARCH:=all
endef

define Build/Compile
endef

define Package/dn-status/install
	$(INSTALL_DIR) $(1)/usr/libexec/dn-status $(1)/etc/init.d $(1)/www/dn-status/cgi-bin
	$(INSTALL_BIN) ./files/usr/libexec/dn-status/status $(1)/usr/libexec/dn-status/
	$(INSTALL_BIN) ./files/etc/init.d/dn-status $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/www/dn-status/cgi-bin/status $(1)/www/dn-status/cgi-bin/
	$(INSTALL_DATA) ./files/www/dn-status/index.html $(1)/www/dn-status/
endef

$(eval $(call BuildPackage,dn-status))
