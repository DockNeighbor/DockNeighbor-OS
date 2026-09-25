include $(TOPDIR)/rules.mk

# Checks a password against root's entry in /etc/shadow, for dn-net's admin-password verb (the DN device API's
# "change the admin password", which must prove the CURRENT password first). OpenWrt without LuCI has no rpcd and
# no crypt tool, so this is a few lines of C over musl's crypt(3). Compiled, so this package is per target arch.
PKG_NAME:=dn-auth
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=SC4 Technologies

include $(INCLUDE_DIR)/package.mk

define Package/dn-auth
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=DockNeighbor OS root password check (crypt against /etc/shadow)
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) -Wall -Werror -o $(PKG_BUILD_DIR)/verify-root \
		$(PKG_BUILD_DIR)/verify-root.c $(TARGET_LDFLAGS) -lcrypt
endef

define Package/dn-auth/install
	$(INSTALL_DIR) $(1)/usr/libexec/dn-auth
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/verify-root $(1)/usr/libexec/dn-auth/
endef

$(eval $(call BuildPackage,dn-auth))
