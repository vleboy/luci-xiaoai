module("luci.controller.xiaoai-mqtt", package.seeall)

function index()
    entry({"admin", "services", "xiaoai-mqtt"}, alias("admin", "services", "xiaoai-mqtt", "config"), _("XiaoAi MQTT"), 60)
    entry({"admin", "services", "xiaoai-mqtt", "config"}, view("xiaoai-mqtt/index"), _("基本配置"), 10)
    entry({"admin", "services", "xiaoai-mqtt", "log"}, template("xiaoai-mqtt/log"), _("日志"), 20)
    entry({"admin", "services", "xiaoai-mqtt", "status"}, call("get_status")).leaf = true
    entry({"admin", "services", "xiaoai-mqtt", "clear_log"}, call("clear_log"))
    entry({"admin", "services", "xiaoai-mqtt", "download_log"}, call("download_log"))
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

    -- 检查服务进程（同时检查PID文件和进程）
    local pid_file = "/var/run/xiaoai-mqtt.pid"
    local has_pid_file = fs.access(pid_file)
    local pid = nil
    
    if has_pid_file then
        pid = tonumber((fs.readfile(pid_file) or ""):match("%d+"))
    end
    
    local is_running = false
    if pid then
        is_running = (luci.sys.call(string.format("[ -d /proc/%d ]" , pid)) == 0)
    end
    
    if not is_running then
        is_running = (luci.sys.call("pgrep -f 'lua /etc/xiaoai-mqtt/mqtt_client.lua' >/dev/null") == 0)
    end
    
    response.service = is_running and "running" or "stopped"

    -- 读取状态文件
    if fs.access("/var/run/xiaoai-mqtt.status") then
        local content = fs.readfile("/var/run/xiaoai-mqtt.status") or ""
        response.mqtt = content:match("mqtt_connection=(%w+)") or "disconnected"
        response.last_action = content:match("last_action=(.+)") or "N/A"
    end

    -- 获取日志统计
    response.log_stats = string.format("%d|%s",
        tonumber(util.exec("wc -l /var/log/xiaoai-mqtt.log 2>/dev/null | awk '{print $1}'")) or 0,
        util.exec("ls -lh /var/log/xiaoai-mqtt.log 2>/dev/null | awk '{print $5}'") or "0B"
    )

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