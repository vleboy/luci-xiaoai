module("luci.controller.xiaoai-mqtt", package.seeall)

function index()
    entry({"admin", "services", "xiaoai-mqtt"}, alias("admin", "services", "xiaoai-mqtt", "config"), _("XiaoAi MQTT"), 60)
    entry({"admin", "services", "xiaoai-mqtt", "config"}, view("xiaoai-mqtt/index"), _("基本配置"), 10)
    entry({"admin", "services", "xiaoai-mqtt", "log"}, template("xiaoai-mqtt/log"), _("日志"), 20)
    entry({"admin", "services", "xiaoai-mqtt", "status"}, call("get_status")).leaf = true
    entry({"admin", "services", "xiaoai-mqtt", "reconnect"}, call("reconnect_mqtt")).leaf = true
    entry({"admin", "services", "xiaoai-mqtt", "start"}, call("start_service")).leaf = true
    entry({"admin", "services", "xiaoai-mqtt", "stop"}, call("stop_service")).leaf = true
    entry({"admin", "services", "xiaoai-mqtt", "restart"}, call("restart_service")).leaf = true
    entry({"admin", "services", "xiaoai-mqtt", "clear_log"}, call("clear_log"))
    entry({"admin", "services", "xiaoai-mqtt", "download_log"}, call("download_log"))
end

function reconnect_mqtt()
    local fs = require "nixio.fs"
    local util = require "luci.util"
    
    local response = {
        success = false,
        message = ""
    }
    
    -- 检查服务是否运行
    local is_running = (luci.sys.call("pgrep -f 'lua /etc/xiaoai-mqtt/mqtt_client.lua' >/dev/null") == 0)
    
    if not is_running then
        response.message = "服务未运行"
        luci.http.prepare_content("application/json")
        luci.http.write_json(response)
        return
    end
    
    -- 读取订阅进程PID
    local sub_pid = nil
    if fs.access("/var/run/mosquitto_sub.pid") then
        local content = fs.readfile("/var/run/mosquitto_sub.pid") or ""
        sub_pid = tonumber(content:match("%d+"))
    end
    
    if sub_pid then
        -- 发送SIGHUP信号让进程重新连接
        local result = luci.sys.call(string.format("kill -1 %d 2>/dev/null", sub_pid))
        if result == 0 then
            response.success = true
            response.message = "已发送重新连接信号"
            -- 更新状态为连接中
            if fs.access("/var/run/xiaoai-mqtt.status") then
                local status_content = fs.readfile("/var/run/xiaoai-mqtt.status") or ""
                local new_content = {}
                for line in status_content:gmatch("[^\r\n]+") do
                    if not line:match("mqtt_connection=") then
                        table.insert(new_content, line)
                    end
                end
                table.insert(new_content, "mqtt_connection=reconnecting")
                fs.writefile("/var/run/xiaoai-mqtt.status", table.concat(new_content, "\n"))
            end
        else
            response.message = "无法发送信号给进程"
        end
    else
        response.message = "未找到运行中的MQTT订阅进程"
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(response)
end

function get_status()
    local util = require "luci.util"
    local fs = require "nixio.fs"

    local response = {
        service = "stopped",
        mqtt = "disconnected",
        last_action = "N/A",
        log_stats = "0|0B"
    }

    -- 使用 pcall 捕获所有可能的 Lua 错误
    local status, err = pcall(function()
        -- 检查服务进程（优化版）
        local is_running = false
        
        -- 首先检查PID文件
        local pid_file = "/var/run/xiaoai-mqtt.pid"
        if fs.access(pid_file) then
            local pid = tonumber((fs.readfile(pid_file) or ""):match("%d+"))
            if pid then
                -- 检查进程是否存在（使用更高效的方法）
                local proc_dir = "/proc/" .. pid
                is_running = fs.access(proc_dir)
            end
        end
        
        -- 如果PID文件检查失败，回退到pgrep
        if not is_running then
            is_running = (luci.sys.call("pgrep -f 'lua /etc/xiaoai-mqtt/mqtt_client.lua' >/dev/null") == 0)
        end
        
        response.service = is_running and "running" or "stopped"

        -- 读取状态文件
        local status_cache = {}
        if fs.access("/var/run/xiaoai-mqtt.status") then
            local content = fs.readfile("/var/run/xiaoai-mqtt.status") or ""
            for line in content:gmatch("[^\r\n]+") do
                local key, value = line:match("([^=]+)=(.+)")
                if key and value then
                    status_cache[key] = value
                end
            end
            
            response.mqtt = status_cache.mqtt_connection or "disconnected"
            response.last_action = status_cache.last_action or "N/A"
        end

        -- 获取日志统计
        local log_file = "/var/log/xiaoai-mqtt.log"
        local lines = 0
        local size = "0B"
        
        if fs.access(log_file) then
            -- 获取文件大小
            local stat = fs.stat(log_file)
            if stat then
                local bytes = stat.size
                if bytes < 1024 then
                    size = string.format("%dB", bytes)
                elseif bytes < 1024 * 1024 then
                    size = string.format("%.1fKB", bytes / 1024)
                else
                    size = string.format("%.1fMB", bytes / (1024 * 1024))
                end
            end
            
            -- 获取行数（使用更高效的方法）
            local file = io.open(log_file, "r")
            if file then
                local count = 0
                for _ in file:lines() do
                    count = count + 1
                    if count > 10000 then  -- 限制最大行数检查
                        break
                    end
                end
                lines = count
                file:close()
            end
        end
        
        response.log_stats = string.format("%d|%s", lines, size)
    end)
    
    if not status then
        -- 如果发生错误，将错误信息放入响应中（便于调试）
        response.last_action = "错误: " .. tostring(err)
        response.service = "error"
    end

    -- 输出 JSON
    luci.http.prepare_content("application/json")
    luci.http.write_json(response)
end

-- clear_log 和 download_log 函数保持不变

function clear_log()
    local fs = require "nixio.fs"
    fs.writefile("/var/log/xiaoai-mqtt.log", "")
    luci.http.redirect(luci.dispatcher.build_url("admin/services/xiaoai-mqtt/log"))
end

function download_log()
    local content = nixio.fs.readfile("/var/log/xiaoai-mqtt.log") or ""
    luci.http.header("Content-Disposition", "attachment; filename=xiaoai-mqtt.log")
    luci.http.prepare_content("text/plain")
    luci.http.write(content)
end

function start_service()
    local response = {
        success = false,
        message = ""
    }
    
    local uci = require "luci.model.uci".cursor()
    
    -- 启用服务配置
    uci:set("xiaoai-mqtt", "main", "enabled", "1")
    uci:commit("xiaoai-mqtt")
    
    -- 检查服务是否已经在运行
    local is_running = (luci.sys.call("pgrep -f 'lua /etc/xiaoai-mqtt/mqtt_client.lua' >/dev/null") == 0)
    
    if is_running then
        response.success = true -- 已经在运行也算成功
        response.message = "服务已经在运行"
        luci.http.prepare_content("application/json")
        luci.http.write_json(response)
        return
    end
    
    -- 启动服务
    local result = luci.sys.call("/etc/init.d/xiaoai-mqtt start >/dev/null 2>&1")
    
    if result == 0 then
        response.success = true
        response.message = "服务启动成功"
        
        -- 更新状态文件
        local fs = require "nixio.fs"
        if fs.access("/var/run/xiaoai-mqtt.status") then
            local status_content = fs.readfile("/var/run/xiaoai-mqtt.status") or ""
            local new_content = {}
            for line in status_content:gmatch("[^\r\n]+") do
                if not line:match("last_action=") then
                    table.insert(new_content, line)
                end
            end
            table.insert(new_content, "last_action=服务已启动")
            fs.writefile("/var/run/xiaoai-mqtt.status", table.concat(new_content, "\n"))
        end
    else
        response.message = "服务启动失败"
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(response)
end

function stop_service()
    local response = {
        success = false,
        message = ""
    }
    
    local uci = require "luci.model.uci".cursor()
    
    -- 禁用服务配置
    uci:set("xiaoai-mqtt", "main", "enabled", "0")
    uci:commit("xiaoai-mqtt")
    
    -- 检查服务是否在运行
    local is_running = (luci.sys.call("pgrep -f 'lua /etc/xiaoai-mqtt/mqtt_client.lua' >/dev/null") == 0)
    
    if not is_running then
        response.success = true -- 未运行也算停用成功
        response.message = "服务未在运行"
        luci.http.prepare_content("application/json")
        luci.http.write_json(response)
        return
    end
    
    -- 停止服务
    local result = luci.sys.call("/etc/init.d/xiaoai-mqtt stop >/dev/null 2>&1")
    
    if result == 0 then
        response.success = true
        response.message = "服务停止成功"
        
        -- 更新状态文件
        local fs = require "nixio.fs"
        if fs.access("/var/run/xiaoai-mqtt.status") then
            local status_content = fs.readfile("/var/run/xiaoai-mqtt.status") or ""
            local new_content = {}
            for line in status_content:gmatch("[^\r\n]+") do
                if not line:match("last_action=") then
                    table.insert(new_content, line)
                end
            end
            table.insert(new_content, "last_action=服务已停止")
            fs.writefile("/var/run/xiaoai-mqtt.status", table.concat(new_content, "\n"))
        end
    else
        response.message = "服务停止失败"
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(response)
end

function restart_service()
    local response = {
        success = false,
        message = ""
    }
    
    -- 重启服务
    local result = luci.sys.call("/etc/init.d/xiaoai-mqtt restart >/dev/null 2>&1")
    
    if result == 0 then
        response.success = true
        response.message = "服务重启成功"
        
        -- 更新状态文件
        local fs = require "nixio.fs"
        if fs.access("/var/run/xiaoai-mqtt.status") then
            local status_content = fs.readfile("/var/run/xiaoai-mqtt.status") or ""
            local new_content = {}
            for line in status_content:gmatch("[^\r\n]+") do
                if not line:match("last_action=") then
                    table.insert(new_content, line)
                end
            end
            table.insert(new_content, "last_action=服务已重启")
            fs.writefile("/var/run/xiaoai-mqtt.status", table.concat(new_content, "\n"))
        end
    else
        response.message = "服务重启失败"
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(response)
end
