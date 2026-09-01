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
    entry({"admin", "services", "xiaoai-mqtt", "log_data"}, call("get_log_data")).leaf = true
end

-- 更新状态文件中的指定键（公共函数，避免多处重复代码）
local function update_status_file(key, value)
    local fs = require "nixio.fs"
    local status_path = "/var/run/xiaoai-mqtt.status"
    if not fs.access(status_path) then return end
    local content = fs.readfile(status_path) or ""
    local new_content = {}
    for line in content:gmatch("[^\r\n]+") do
        if not line:match("^" .. key .. "=") then
            table.insert(new_content, line)
        end
    end
    table.insert(new_content, key .. "=" .. value)
    fs.writefile(status_path, table.concat(new_content, "\n"))
end

function reconnect_mqtt()
    local response = {
        success = false,
        message = ""
    }
    
    -- 检查服务是否运行（[l]ua 方括号技巧：避免 pgrep 匹配到自身的父 shell）
    local is_running = (luci.sys.call("pgrep -f '[l]ua /etc/xiaoai-mqtt/mqtt_client.lua' >/dev/null") == 0)
    
    if not is_running then
        response.message = "服务未运行"
        luci.http.prepare_content("application/json")
        luci.http.write_json(response)
        return
    end
    
    -- 彻底重启服务以重新建立 MQTT 连接（SIGHUP 对 mosquitto_sub 默认是退出而非重连，故用 restart）
    local result = luci.sys.call("/etc/init.d/xiaoai-mqtt restart >/dev/null 2>&1")
    if result == 0 then
        response.success = true
        response.message = "已发送重新连接请求"
    else
        response.message = "服务重启失败"
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
        
        -- 如果PID文件检查失败，回退到pgrep（[l]ua 方括号技巧避免自匹配）
        if not is_running then
            is_running = (luci.sys.call("pgrep -f '[l]ua /etc/xiaoai-mqtt/mqtt_client.lua' >/dev/null") == 0)
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
            
            -- 获取行数（使用 wc 更高效）
            local n = tonumber(luci.sys.exec("wc -l < " .. log_file) or "")
            lines = n or 0
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
    local fs = require "nixio.fs"
    local content = fs.readfile("/var/log/xiaoai-mqtt.log") or ""
    luci.http.header("Content-Disposition", "attachment; filename=xiaoai-mqtt.log")
    luci.http.prepare_content("text/plain")
    luci.http.write(content)
end

-- 日志页 JSON 数据接口（尾部内容 + 统计，避免整页刷新）
function get_log_data()
    local fs = require "nixio.fs"
    local log_file = "/var/log/xiaoai-mqtt.log"
    local response = {
        tail = "",
        size = "0B",
        lines = 0
    }
    
    if fs.access(log_file) then
        response.tail = luci.sys.exec("tail -n 100 " .. log_file) or ""
        
        local stat = fs.stat(log_file)
        if stat then
            local bytes = stat.size
            if bytes < 1024 then
                response.size = string.format("%dB", bytes)
            elseif bytes < 1024 * 1024 then
                response.size = string.format("%.1fKB", bytes / 1024)
            else
                response.size = string.format("%.1fMB", bytes / (1024 * 1024))
            end
        end
        
        local n = tonumber(luci.sys.exec("wc -l < " .. log_file) or "")
        response.lines = n or 0
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(response)
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
    
    -- 检查服务是否已经在运行（[l]ua 方括号技巧避免自匹配）
    local is_running = (luci.sys.call("pgrep -f '[l]ua /etc/xiaoai-mqtt/mqtt_client.lua' >/dev/null") == 0)
    
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
        update_status_file("last_action", "服务已启动")
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
    
    -- 检查服务是否在运行（[l]ua 方括号技巧避免自匹配）
    local is_running = (luci.sys.call("pgrep -f '[l]ua /etc/xiaoai-mqtt/mqtt_client.lua' >/dev/null") == 0)
    
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
        update_status_file("last_action", "服务已停止")
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
        update_status_file("last_action", "服务已重启")
    else
        response.message = "服务重启失败"
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(response)
end
