include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-xiaoai-mqtt
PKG_VERSION:=25.12.10.01
PKG_RELEASE:=1

PKG_MAINTAINER:=vleboy <vleboy@gmail.com>
PKG_LICENSE:=GPL-3.0

PKG_CONFIG_DEPENDS:=CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_MQTT_SSL

LUCI_TITLE:=XiaoAi MQTT Control Interface
LUCI_DEPENDS:=+lua +mosquitto-client-ssl
LUCI_PKGARCH:=all



include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/conffiles
/etc/config/xiaoai-mqtt
/etc/xiaoai-mqtt/mqtt_client.lua
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

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	# LuCI相关文件
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/controller/xiaoai-mqtt.lua $(1)/usr/lib/lua/luci/controller/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/xiaoai-mqtt
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/model/cbi/xiaoai-mqtt/*.lua $(1)/usr/lib/lua/luci/model/cbi/xiaoai-mqtt/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/xiaoai-mqtt
	$(INSTALL_DATA) ./luasrc/view/xiaoai-mqtt/*.htm $(1)/usr/lib/lua/luci/view/xiaoai-mqtt/

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
	$(INSTALL_BIN) ./root/etc/xiaoai-mqtt/status.sh $(1)/etc/xiaoai-mqtt/

	# 安装启动脚本
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/xiaoai-mqtt $(1)/etc/init.d/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
