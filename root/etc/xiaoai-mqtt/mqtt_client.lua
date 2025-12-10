local uci = require "luci.model.uci".cursor()
local nixio = require "nixio"  -- 加载 nixio 库

-- 定义 os.capture 函数（用于执行命令并捕获输出）
function os.capture(cmd, raw)
    local f = assert(io.popen(cmd, 'r'))
    local s = assert(f:read('*a'))
    f:close()
    if raw then return s end
    s = string.gsub(s, '^%s+', '')
    s = string.gsub(s, '%s+$', '')
    s = string.gsub(s, '[\n\r]+', ' ')
    return s
end

-- 常量定义
local LOG_FILE = "/var/log/xiaoai-mqtt.log"
local STATUS_FILE = "/var/run/xiaoai-mqtt.status"
local SUB_PID_FILE = "/var/run/mosquitto_sub.pid"
local SUB_OUTPUT_FILE = "/tmp/mosquitto_sub.out"
local PID_FILE = "/var/run/xiaoai-mqtt.pid"


-- 日志轮转配置
local LOG_MAX_SIZE = 1024 * 1024  -- 1MB
local LOG_MAX_FILES = 5

-- 删除旧的rotate_log_if_needed函数，使用新的rotate_log函数代替

-- 简单的日志记录函数（避免递归调用）
local function write_log(msg)
    local fs = require "nixio.fs"
    
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local log_message = string.format("[%s] %s\n", timestamp, msg)
    
    -- 直接写入日志文件，不调用轮转函数（避免递归）
    local pcall_success, write_result = pcall(function()
        return fs.writefile("/var/log/xiaoai-mqtt.log", log_message, true)
    end)
    
    if not pcall_success or not write_result then
        -- 如果写入失败，尝试创建日志文件
        local create_pcall_success, create_write_result = pcall(function()
            -- 先尝试创建空文件
            fs.writefile("/var/log/xiaoai-mqtt.log", "")
            -- 然后写入日志
            return fs.writefile("/var/log/xiaoai-mqtt.log", log_message, true)
        end)
        
        if not create_pcall_success or not create_write_result then
            -- 如果还是失败，输出到标准错误（最后的手段）
            io.stderr:write(string.format("[%s] 日志写入失败: %s\n", timestamp, msg))
        end
    end
end

-- 独立的日志轮转函数（不调用write_log）
local function rotate_log()
    local fs = require "nixio.fs"
    local log_file = "/var/log/xiaoai-mqtt.log"
    
    -- 检查文件是否存在和大小
    if not fs.access(log_file) then
        return
    end
    
    local stat = fs.stat(log_file)
    if not stat or stat.size < LOG_MAX_SIZE then
        return
    end
    
    -- 执行轮转（不调用write_log，直接操作）
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local rotate_msg = string.format("[%s] 日志文件达到限制，开始轮转...\n", timestamp)
    fs.writefile(log_file, rotate_msg, true)
    
    -- 删除最旧的日志文件
    local oldest_log = string.format("%s.%d", log_file, LOG_MAX_FILES - 1)
    if fs.access(oldest_log) then
        fs.unlink(oldest_log)
    end
    
    -- 重命名现有日志文件
    for i = LOG_MAX_FILES - 2, 1, -1 do
        local old_name = string.format("%s.%d", log_file, i)
        local new_name = string.format("%s.%d", log_file, i + 1)
        if fs.access(old_name) then
            fs.rename(old_name, new_name)
        end
    end
    
    -- 重命名当前日志文件
    local rotated_name = string.format("%s.1", log_file)
    fs.rename(log_file, rotated_name)
    
    -- 创建新的日志文件
    fs.writefile(log_file, "")
    fs.chmod(log_file, 644)
    
    local complete_msg = string.format("[%s] 日志轮转完成\n", timestamp)
    fs.writefile(log_file, complete_msg, true)
end

-- 检查并执行日志轮转（在适当的时候调用）
local function check_and_rotate_log()
    -- 每100次日志写入检查一次轮转
    local rotate_counter = 0
    return function()
        rotate_counter = rotate_counter + 1
        if rotate_counter % 100 == 0 then
            rotate_log()
        end
    end
end

local check_log_rotation = check_and_rotate_log()

-- 状态更新（优化版）
local last_status_update = {}
local status_update_count = 0

local function update_status(key, value)
    -- 检查值是否真的改变了
    if last_status_update[key] == value then
        return
    end
    
    last_status_update[key] = value
    
    local fs = require "nixio.fs"
    local status_content = fs.readfile(STATUS_FILE) or ""
    local content = {}
    local updated = false
    
    for line in status_content:gmatch("[^\r\n]+") do
        if line:match("^"..key.."=") then
            table.insert(content, string.format("%s=%s", key, value))
            updated = true
        else
            table.insert(content, line)
        end
    end
    
    if not updated then
        table.insert(content, string.format("%s=%s", key, value))
    end
    
    -- 限制状态文件写入频率（每10次更新写入一次，除非是关键状态）
    status_update_count = status_update_count + 1
    local should_write = (status_update_count % 10 == 0) or 
                        (key == "mqtt_connection") or 
                        (key == "service_status") or
                        (key == "last_action")
    
    if should_write then
        fs.writefile(STATUS_FILE, table.concat(content, "\n"))
        fs.chmod(STATUS_FILE, 644)
    end
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
    
    -- 使用更高效的文件读取方式，只读取新内容
    local file = io.open(SUB_OUTPUT_FILE, "r")
    if not file then return end
    
    local content = file:read("*a")
    file:close()
    
    if content == "" then return end
    
    -- 限制读取大小，防止内存占用过大
    content = content:sub(1, 8192)  -- 增加到8KB，但限制最大读取
    
    -- 错误检测
    if content:find("Connection refused") then
        write_log("连接被拒绝: "..content:match("Connection refused.-\n"))
        os.exit(1)
    end
    if content:find("Not authorized") then
        write_log("订阅未授权，请检查主题绑定")
        os.exit(1)
    end
    
    -- 缓存配置，避免每次消息都读取UCI
    local wol_config_cache = nil
    local shutdown_config_cache = nil
    
    -- 消息处理
    local processed_count = 0
    for line in content:gmatch("[^\r\n]+") do
        processed_count = processed_count + 1
        if processed_count > 50 then  -- 限制单次处理的消息数量
            write_log("警告：单次处理消息过多，跳过剩余消息")
            break
        end
        
        local topic, payload = line:match("(%S+)%s+(.+)$")
        if topic and payload then
            -- 延迟日志记录，减少I/O操作
            local should_log = (processed_count <= 5)  -- 只记录前5条消息
            
            if should_log then
                write_log("原始输出: "..line)
            end
            
            -- WOL处理
            if not wol_config_cache then
                wol_config_cache = uci:get_all("xiaoai-mqtt", "wol") or {}
            end
            
            for _, trigger in ipairs(wol_config_cache.on_msgs or {}) do
                if payload == trigger then
                    execute_wol(wol_config_cache.mac)
                    break
                end
            end
            
            -- 关机处理
            if not shutdown_config_cache then
                shutdown_config_cache = uci:get_all("xiaoai-mqtt", "shutdown") or {}
            end
            
            for _, trigger in ipairs(shutdown_config_cache.off_msgs or {}) do
                if payload == trigger then
                    execute_shutdown(shutdown_config_cache.ip, shutdown_config_cache.user, shutdown_config_cache.pass)
                    break
                end
            end
        end
    end
    
    -- 清空已处理内容（使用truncate而不是重定向）
    os.execute("truncate -s 0 "..SUB_OUTPUT_FILE)
end

-- 主循环
local function main_loop()
    local reconnect_delay = 5
    local pid = nil
    -- 更新服务状态
    update_status("service_status", "running")
    update_status("mqtt_connection", "connecting")
    
    while true do
        local success, err = pcall(function()
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
                    write_log(string.format("启动进程失败，等待 %d 秒后重试...", reconnect_delay))
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
        end)
        
        if not success then
            write_log("主循环错误: " .. tostring(err))
            write_log("等待 10 秒后继续...")
            nixio.nanosleep(10)
        end
    end
end

-- 强制重新连接函数
local function force_reconnect()
    write_log("强制重新连接MQTT...")
    update_status("mqtt_connection", "reconnecting")
    
    -- 读取当前PID
    local sub_pid = read_pid_file(SUB_PID_FILE)
    if sub_pid then
        -- 终止当前进程
        os.execute(string.format("kill -9 %d 2>/dev/null", sub_pid))
        write_log(string.format("已终止订阅进程 PID: %d", sub_pid))
        os.remove(SUB_PID_FILE)
    end
end

-- 写入PID文件
local function write_pid_file()
    local pid = nixio.getpid()
    local fs = require "nixio.fs"
    
    write_log(string.format("开始写入PID文件，当前PID: %d", pid))
    write_log(string.format("PID文件路径: %s", PID_FILE))
    
    -- 确保目录存在
    local dir = "/var/run"
    if not fs.access(dir) then
        write_log("目录 /var/run 不存在，尝试创建...")
        local mkdir_success, mkdir_err = pcall(function()
            fs.mkdir(dir)
        end)
        if mkdir_success then
            write_log("目录创建成功")
        else
            write_log("目录创建失败: " .. tostring(mkdir_err))
        end
    else
        write_log("目录 /var/run 已存在")
    end
    
    -- 检查目录权限
    local dir_stat = fs.stat(dir)
    if dir_stat then
        write_log(string.format("目录权限: %o", dir_stat.mode))
    end
    
    -- 尝试写入PID文件
    write_log("尝试写入PID文件...")
    local pcall_success, write_result = pcall(function()
        return fs.writefile(PID_FILE, tostring(pid))
    end)
    
    if pcall_success and write_result then  -- pcall成功且writefile返回true
        fs.chmod(PID_FILE, 644)
        write_log(string.format("PID文件写入成功: %d", pid))
        
        -- 验证文件是否真的存在
        if fs.access(PID_FILE) then
            local file_content = fs.readfile(PID_FILE) or ""
            write_log(string.format("验证PID文件内容: %s", file_content))
            return true
        else
            write_log("警告：PID文件写入成功但文件不存在")
            return false
        end
    else
        if not pcall_success then
            write_log("无法写入PID文件，pcall错误: " .. tostring(write_result))
        else
            write_log("无法写入PID文件，writefile返回false")
        end
        write_log("路径: " .. PID_FILE)
        return false
    end
end

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
    if sig == 1 then  -- SIGHUP: 重新连接信号
        write_log("收到重新连接信号(SIGHUP)，重新启动MQTT连接...")
        -- 更新状态为重新连接中
        update_status("mqtt_connection", "reconnecting")
        -- 调用强制重新连接函数
        force_reconnect()
    else
        write_log(string.format("收到信号 %d，执行清理...", sig))
        cleanup()
        os.exit(0)
    end
end

-- 注册信号处理 - 尝试使用函数，如果失败则使用字符串
local function register_signal_handlers()
    -- 尝试注册SIGHUP处理函数
    local success, err = pcall(function()
        nixio.signal(1, _G.handle_signal)
    end)
    
    if not success then
        write_log("无法注册SIGHUP函数处理，使用默认处理: " .. tostring(err))
        nixio.signal(1, "dfl")  -- 使用默认处理而不是无效的"handle"
    else
        write_log("SIGHUP信号处理函数注册成功")
    end
    
    -- 其他信号使用字符串处理
    nixio.signal(15, "ign")  -- SIGTERM:忽略信号
    nixio.signal(2, "ign")   -- SIGINT:忽略信号
end

-- 服务入口
-- 首先输出到标准错误，确保即使日志系统有问题也能看到
io.stderr:write(string.format("[%s] ====== 服务初始化开始 ======\n", os.date("%Y-%m-%d %H:%M:%S")))
write_log("====== 服务初始化开始 ======")
if not write_pid_file() then
    io.stderr:write(string.format("[%s] 错误：无法写入PID文件，服务启动失败\n", os.date("%Y-%m-%d %H:%M:%S")))
    write_log("错误：无法写入PID文件，服务启动失败")
    os.exit(1)
end
io.stderr:write(string.format("[%s] PID文件写入成功，注册信号处理\n", os.date("%Y-%m-%d %H:%M:%S")))
register_signal_handlers()
update_status("service_status", "running")
io.stderr:write(string.format("[%s] 进入主循环\n", os.date("%Y-%m-%d %H:%M:%S")))
local ok, err = pcall(main_loop)
cleanup()
if not ok then
    io.stderr:write(string.format("[%s] 服务异常退出: %s\n", os.date("%Y-%m-%d %H:%M:%S"), tostring(err)))
    write_log(string.format("服务异常退出: %s", tostring(err)))
    os.exit(1)
end
