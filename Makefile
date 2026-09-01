include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-xiaoai-mqtt
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=vleboy <vleboy@gmail.com>
PKG_LICENSE:=GPL-3.0

LUCI_TITLE:=XiaoAi MQTT Control Interface
LUCI_DEPENDS:=+luci-base +luci-lua-nixio +mosquitto-client-nossl +etherwake +samba4-admin
LUCI_PKGARCH:=all



include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/conffiles
/etc/config/xiaoai-mqtt
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
    if [ -f /etc/uci-defaults/luci-xiaoai-mqtt ]; then
        ( . /etc/uci-defaults/luci-xiaoai-mqtt ) && rm -f /etc/uci-defaults/luci-xiaoai-mqtt
        /etc/init.d/xiaoai-mqtt enable || true
    fi
    exit 0
}
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
    /etc/init.d/xiaoai-mqtt stop || true
    /etc/init.d/xiaoai-mqtt disable || true
    exit 0
}
endef

define Package/$(PKG_NAME)/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
    rm -f /var/run/xiaoai-mqtt.pid
    rm -f /var/run/xiaoai-mqtt.status
    rm -f /var/log/xiaoai-mqtt.log*
    exit 0
}
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	# LuCI相关文件
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/controller/xiaoai-mqtt.lua $(1)/usr/lib/lua/luci/controller/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/xiaoai-mqtt
	$(INSTALL_DATA) ./luasrc/view/xiaoai-mqtt/log.htm $(1)/usr/lib/lua/luci/view/xiaoai-mqtt/

	# 静态资源文件
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/xiaoai-mqtt
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/xiaoai-mqtt/index.js $(1)/www/luci-static/resources/view/xiaoai-mqtt/
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/xiaoai-mqtt/style.css $(1)/www/luci-static/resources/view/xiaoai-mqtt/

	# 系统配置文件
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/xiaoai-mqtt $(1)/etc/config/

	# 主程序文件
	$(INSTALL_DIR) $(1)/etc/xiaoai-mqtt
	$(INSTALL_BIN) ./root/etc/xiaoai-mqtt/mqtt_client.lua $(1)/etc/xiaoai-mqtt/

	# UCI Defaults
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/luci-xiaoai-mqtt $(1)/etc/uci-defaults/

	# 安装启动脚本
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/xiaoai-mqtt $(1)/etc/init.d/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
