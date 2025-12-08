local uci = luci.model.uci.cursor()
local sys = require "luci.sys"

m = Map("xiaoai-mqtt", translate("基本配置"), translate("配置MQTT服务参数和设备控制选项"))

-- 配置保存后跳转日志页面
function m.on_after_save(self)
    os.execute("/etc/init.d/xiaoai-mqtt restart >/dev/null 2>&1")
    luci.http.redirect(luci.dispatcher.build_url("admin/services/xiaoai-mqtt/basic"))
end

-- 服务状态显示
s = m:section(SimpleSection, nil, translate("服务状态"))
s.template = "xiaoai-mqtt/status"

-- MQTT配置
s = m:section(NamedSection, "mqtt", "mqtt", translate("MQTT参数"))
s.anonymous = true
s.addremove = false

local broker = s:option(TextValue, "mqtt_broker", translate("服务器地址"))
broker.placeholder = "bemfa.com"
broker.rows = 1
broker.size = 30
broker.rmempty = false



local port = s:option(Value, "mqtt_port", translate("端口"))
port.datatype = "port"
port.rmempty = false
port.default = "9501"

local client_id = s:option(Value, "mqtt_client_id", translate("客户端ID"))
client_id.placeholder = "随机生成"
client_id.rmempty = false
client_id.validate = function(self, value)
    if value and #value > 0 then return value end
    return nixio.bin.hexlify(nixio.bin.urandom(8))
end

local topic = s:option(Value, "mqtt_topic", translate("订阅主题"))
topic.placeholder = "default_topic"
topic.rmempty = false
topic.validate = function(self, value)
    if not value or #value == 0 then return nil, "主题不能为空" end
    return value
end

-- WOL配置
s = m:section(NamedSection, "wol", "wol", translate("网络唤醒设置"))
s.anonymous = true
s.addremove = false

local mac = s:option(Value, "mac", translate("目标MAC地址"))
mac.placeholder = "00:11:22:33:44:55"
mac.rmempty = false
mac.datatype = "macaddr"

local on_msgs = s:option(DynamicList, "on_msgs", translate("触发消息"))
on_msgs.placeholder = "on"
on_msgs.rmempty = true

-- 关机配置
s = m:section(NamedSection, "shutdown", "shutdown", translate("远程关机设置"))
s.anonymous = true
s.addremove = false

local ip = s:option(Value, "ip", translate("目标IP地址"))
ip.datatype = "ip4addr"
ip.rmempty = false

local user = s:option(Value, "user", translate("用户名"))
user.placeholder = "admin"
user.rmempty = false
user.validate = function(self, value)
    if not value or #value == 0 then return nil, "用户名不能为空" end
    return value
end

local pass = s:option(Value, "pass", translate("密码"))
pass.password = true
pass.rmempty = false
pass.validate = function(self, value)
    if not value or #value == 0 then return nil, "密码不能为空" end
    return value
end

local off_msgs = s:option(DynamicList, "off_msgs", translate("关机指令"))
off_msgs.placeholder = "off"
off_msgs.rmempty = true

-- 服务控制
s = m:section(NamedSection, "main", "service", translate("服务控制"))
s.anonymous = true
s.addremove = false

local enable = s:option(Flag, "enabled", translate("启用服务"))
enable.default = "0"
enable.rmempty = false
enable.optional = false

-- 配置验证函数
local function validate_config()
    local config = uci:get_all("xiaoai-mqtt", "mqtt") or {}
    if not config.mqtt_client_id or config.mqtt_client_id == "" then
        return false, "客户端ID不能为空"
    end
    if not tonumber(config.mqtt_port) or tonumber(config.mqtt_port) < 1 or tonumber(config.mqtt_port) > 65535 then
        return false, "端口号无效"
    end
    return true
end

-- 重写启用选项的写操作
function enable.write(self, section, value)
    local ok, err = validate_config()
    if value == "1" and not ok then
        -- 显示错误信息并阻止保存
        luci.http.status(500, "Configuration Error")
        luci.http.write_json({ error = err })
        return
    end
    
    -- 提交配置变更
    uci:set("xiaoai-mqtt", section, "enabled", value)
    uci:commit("xiaoai-mqtt")
    
    -- 启停服务
    if value == "1" then
        os.execute("/etc/init.d/xiaoai-mqtt restart >/dev/null 2>&1 &")
    else
        os.execute("/etc/init.d/xiaoai-mqtt stop >/dev/null 2>&1 &")
    end
end

return m