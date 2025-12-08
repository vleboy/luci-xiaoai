local uci = require "luci.model.uci".cursor()
local nixio = require "nixio"  -- 加载 nixio 库
-- 常量定义
local LOG_FILE = "/var/log/xiaoai-mqtt.log"
local STATUS_FILE = "/var/run/xiaoai-mqtt.status"
local SUB_PID_FILE = "/var/run/mosquitto_sub.pid"
local SUB_OUTPUT_FILE = "/tmp/mosquitto_sub.out"
local PID_FILE = "/var/run/xiaoai-mqtt.pid"


-- 日志记录
local function write_log(msg)
    local fs = require "nixio.fs"
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local log_message = string.format("[%s] %s\n", timestamp, msg)
    fs.writefile("/var/log/xiaoai-mqtt.log", log_message, true)
    if not fs.chmod("/var/log/xiaoai-mqtt.log", 644) then
        log_message = string.format("Failed to chmod log file: %s", "/var/log/xiaoai-mqtt.log")
        fs.writefile("/var/log/xiaoai-mqtt.log", log_message, true)
    end
end

-- 状态更新
local function update_status(key, value)
    local content = {}
    local fs = require "nixio.fs"
    local status_content = fs.readfile(STATUS_FILE) or ""
    for line in status_content:gmatch("[^\r\n]+") do
        if not line:match(key.."=") then table.insert(content, line) end
    end
    table.insert(content, string.format("%s=%s", key, value))
    fs.writefile(STATUS_FILE, table.concat(content, "\n"))
    fs.chmod(STATUS_FILE, 644)
end

-- WOL执行
local function execute_wol(mac)
    local cmd = string.format("/usr/bin/etherwake -i br-lan %q", mac)
    local result = os.capture(cmd)
    write_log(string.format("执行开机: %s (%s)", cmd, result and "成功" or "失败"))
    update_status("last_action", os.date().." WOL发送至 "..mac)
end

-- SMB关机
local function execute_shutdown(ip, user, pass)
    local cmd = string.format("/usr/bin/net rpc shutdown -I %s -U '%s%%%s' -t 1 -f", ip, user, pass)
    local result = os.capture(cmd)
    write_log(string.format("执行关机: %s (%s)", cmd, result and "成功" or "失败"))
    update_status("last_action", os.date().." 关闭 "..ip)
end

-- 读取PID文件
local function read_pid_file(path)
    local path = path or SUB_PID_FILE
    -- 尝试使用nixio.fs模块读取文件
    local fs = require "nixio.fs"
    local content = fs.readfile(path) or ""
    if content == "" then
        write_log("无法读取PID文件: " .. path)
        return nil
    end
    local pid = tonumber(content:match("%d+"))
    if not pid then
        write_log("PID文件格式错误: " .. path)
        return nil
    end
    return pid
end

-- 启动mosquitto_sub进程
local function start_mosquitto_sub()
    local config = uci:get_all("xiaoai-mqtt", "mqtt") or {}
    
    -- 参数验证
    local required = {"mqtt_broker", "mqtt_port", "mqtt_topic", "mqtt_client_id"}
    for _, k in ipairs(required) do
        if not config[k] or config[k] == "" then
            write_log("配置错误: 缺少必要参数 "..k)
            return nil
        end
    end

    -- 构建命令
    local cmd = string.format(
        "mosquitto_sub -h '%s' -p %d -t '%s' -i '%s' --protocol-version mqttv311 -q 1 -v > '%s' 2>&1 & echo $! > '%s'",
        config.mqtt_broker,
        config.mqtt_port,
        config.mqtt_topic,
        config.mqtt_client_id,
        SUB_OUTPUT_FILE,
        SUB_PID_FILE
    )
    
    write_log("启动命令: "..cmd:gsub(" -P '%S+'", "")) -- 安全过滤
    local handle = io.popen(cmd)
local output = handle:read("*a")
handle:close()
write_log("启动命令输出: "..(output or "无输出"))
    
-- 获取PID
local pid = nil
local function get_pid_from_output(output)
    local pattern = "%d+"
    local pid_str = string.match(output, pattern)
    if pid_str then
        pid = tonumber(pid_str)
    end
end
get_pid_from_output(output)
if not pid then
    write_log("错误: 无法获取PID，请检查权限")
    return nil
end
    
    if not pid then
        write_log("错误: 无法获取PID，请检查权限")
        return nil
    end
    return pid
end

-- 进程存活检查
local function is_process_alive(pid)
    if not pid then return false end
    local stat = nixio.fs.stat("/proc/"..pid)
    return stat and stat.type == "dir"
end

-- 处理订阅消息
local function process_messages()
    local fs = require "nixio.fs"
    local content = fs.readfile(SUB_OUTPUT_FILE) or ""
    if content == "" then return end
    
    -- 限制读取大小
    content = content:sub(1, 4096)
    fs.chmod(SUB_OUTPUT_FILE, 644)
    
    -- 错误检测
    if content:find("Connection refused") then
        write_log("连接被拒绝: "..content:match("Connection refused.-\n"))
        os.exit(1)
    end
    if content:find("Not authorized") then
        write_log("订阅未授权，请检查主题绑定")
        os.exit(1)
    end
    
    -- 消息处理
    for line in content:gmatch("[^\r\n]+") do
        write_log("原始输出: "..line)
        local topic, payload = line:match("(%S+)%s+(.+)$")
        if topic and payload then
            -- WOL处理
            local wol_config = uci:get_all("xiaoai-mqtt", "wol") or {}
            for _, trigger in ipairs(wol_config.on_msgs or {}) do
                if payload == trigger then
                    execute_wol(wol_config.mac)
                    break
                end
            end
            
            -- 关机处理
            local shutdown_config = uci:get_all("xiaoai-mqtt", "shutdown") or {}
            for _, trigger in ipairs(shutdown_config.off_msgs or {}) do
                if payload == trigger then
                    execute_shutdown(shutdown_config.ip, shutdown_config.user, shutdown_config.pass)
                    break
                end
            end
        end
    end
    
    -- 清空已处理内容
    os.execute(">"..SUB_OUTPUT_FILE)
end

-- 主循环
local function main_loop()
    local reconnect_delay = 5
    local pid = nil
    -- 更新服务状态
    update_status("service_status", "running")
    update_status("mqtt_connection", "connecting")
    while true do
        if not is_process_alive(pid) then
            -- 清理旧进程
            if pid then
                write_log(string.format("进程 %d 已终止，等待重启...", pid))
                os.execute("kill -9 "..pid.." 2>/dev/null")
                os.remove(SUB_PID_FILE)
            end
            
            -- 启动新进程
            pid = start_mosquitto_sub()
            if not pid then
                reconnect_delay = math.min(reconnect_delay * 2, 300)
                nixio.nanosleep(reconnect_delay)
            else
                write_log(string.format("进程启动成功 PID: %d", pid))
                reconnect_delay = 5
            end
        else
            -- 处理消息
            process_messages()
            update_status("mqtt_connection", "connected") 
            nixio.nanosleep(3)
            update_status("service_heartbeat", os.date("%Y-%m-%d %H:%M:%S"))
        end
    end
end

-- 写入PID文件
local function write_pid_file()
    local pid = nixio.getpid()
    local fs = require "nixio.fs"
    if fs.writefile(PID_FILE, tostring(pid)) then
        fs.chmod(PID_FILE, 644)
        write_log(string.format("已写入PID文件: %d", pid))
        return true
    end
    write_log("无法写入PID文件")
    return false
end

-- read_pid_file函数已在上方定义，此处删除重复定义

local function cleanup()
    -- 终止主进程（通过 PID 文件）
    local main_pid = read_pid_file(PID_FILE)
    if main_pid then
        os.execute(string.format("kill -9 %d 2>/dev/null", main_pid))
        write_log(string.format("已终止主进程 PID: %d", main_pid))
    end

    -- 终止 mosquitto_sub 进程（通过 PID 文件）
    local sub_pid = read_pid_file(SUB_PID_FILE)
    if sub_pid then
        os.execute(string.format("kill -9 %d 2>/dev/null", sub_pid))
        write_log(string.format("已终止订阅进程 PID: %d", sub_pid))
    end

    -- 删除残留文件
    os.remove(SUB_PID_FILE)
    os.remove(SUB_OUTPUT_FILE)
    os.remove(PID_FILE)
    write_log("清理完成")
end

-- 信号处理函数必须是全局函数，否则无法被正确调用
_G.handle_signal = function(sig)
    write_log(string.format("收到信号 %d，执行清理...", sig))
    cleanup()
    os.exit(0)
end

-- 注册信号处理
nixio.signal(15, "ign")  -- SIGTERM:忽略信号
nixio.signal(2, "ign")   -- SIGINT:忽略信号
nixio.signal(1, "ign")   -- SIGHUP:忽略信号

-- 服务入口
write_log("====== 服务初始化开始 ======")
write_pid_file()
update_status("service_status", "running")
local ok, err = pcall(main_loop)
cleanup()
if not ok then
    write_log(string.format("服务异常退出: %s", tostring(err)))
    os.exit(1)
end
