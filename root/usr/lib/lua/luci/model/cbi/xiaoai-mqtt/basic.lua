local uci = luci.model.uci.cursor()
local sys = require "luci.sys"

m = Map("xiaoai-mqtt", translate("基本配置"), translate("配置MQTT服务参数和设备控制选项"))

-- 配置保存后跳转日志页面
function m.on_after_save(self)
    -- 获取当前配置
    local uci = luci.model.uci.cursor()
    local config = {}
    
    -- 获取MQTT配置
    config.mqtt = uci:get_all("xiaoai-mqtt", "mqtt") or {}
    
    -- 获取WOL配置
    config.wol = uci:get_all("xiaoai-mqtt", "wol") or {}
    
    -- 获取关机配置
    config.shutdown = uci:get_all("xiaoai-mqtt", "shutdown") or {}
    
    -- 构建日志消息
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local log_message = string.format("[%s] 配置已保存\n", timestamp)
    
    -- 记录MQTT配置（隐藏敏感信息）
    log_message = log_message .. string.format("  MQTT配置:\n")
    log_message = log_message .. string.format("    服务器地址: %s\n", config.mqtt.mqtt_broker or "未设置")
    log_message = log_message .. string.format("    端口: %s\n", config.mqtt.mqtt_port or "未设置")
    log_message = log_message .. string.format("    客户端ID: %s\n", config.mqtt.mqtt_client_id or "未设置")
    log_message = log_message .. string.format("    订阅主题: %s\n", config.mqtt.mqtt_topic or "未设置")
    
    -- 记录WOL配置
    log_message = log_message .. string.format("  WOL配置:\n")
    log_message = log_message .. string.format("    MAC地址: %s\n", config.wol.mac or "未设置")
    if config.wol.on_msgs then
        log_message = log_message .. string.format("    触发消息: %s\n", table.concat(config.wol.on_msgs, ", "))
    else
        log_message = log_message .. string.format("    触发消息: 未设置\n")
    end
    
    -- 记录关机配置（隐藏密码）
    log_message = log_message .. string.format("  关机配置:\n")
    log_message = log_message .. string.format("    IP地址: %s\n", config.shutdown.ip or "未设置")
    log_message = log_message .. string.format("    用户名: %s\n", config.shutdown.user or "未设置")
    log_message = log_message .. string.format("    密码: %s\n", config.shutdown.pass and "******" or "未设置")
    if config.shutdown.off_msgs then
        log_message = log_message .. string.format("    关机指令: %s\n", table.concat(config.shutdown.off_msgs, ", "))
    else
        log_message = log_message .. string.format("    关机指令: 未设置\n")
    end
    
    -- 写入日志文件
    local log_file = "/var/log/xiaoai-mqtt.log"
    local file, err = io.open(log_file, "a")
    if file then
        file:write(log_message .. "\n")
        file:close()
    else
        -- 如果文件不存在或无法打开，尝试创建并写入
        local create_success, create_err = pcall(function()
            local f = io.open(log_file, "w") -- 尝试创建新文件
            if f then
                f:write(log_message .. "\n")
                f:close()
            else
                error(create_err or "无法创建或写入日志文件")
            end
        end)
        if not create_success then
            luci.sys.syslog("error", "XiaoAi MQTT: 无法写入日志文件 %s: %s", log_file, tostring(create_err))
        end
    end
    
    -- 重启服务
    local status, exitcode = sys.call("/etc/init.d/xiaoai-mqtt restart >/dev/null 2>&1")
    if status ~= 0 then
        luci.sys.syslog("error", "XiaoAi MQTT: 服务重启失败，退出码: %d", exitcode)
        luci.http.redirect(luci.dispatcher.build_url("admin/services/xiaoai-mqtt/basic?error=restart_failed"))
    else
        luci.http.redirect(luci.dispatcher.build_url("admin/services/xiaoai-mqtt/basic"))
    end
end

-- 服务状态显示
s = m:section(SimpleSection, nil, translate("服务状态"))
s.template = "xiaoai-mqtt/status"

-- 服务控制
s = m:section(NamedSection, "main", "service", translate("服务控制"))
s.anonymous = true
s.addremove = false

local enabled = s:option(Flag, "enabled", translate("启用服务"))
enabled.default = 1
enabled.rmempty = false

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
    -- 如果用户未输入且当前配置中也没有，则生成一个随机ID
    if not self.value or #self.value == 0 then
        return nixio.bin.hexlify(nixio.bin.urandom(8))
    end
    return self.value -- 否则使用当前配置中的值
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

-- 配置保存时验证
function m.on_before_save(self)
    local ok, err = validate_config()
    if not ok then
        return false, err
    end
    return true
end

return m
