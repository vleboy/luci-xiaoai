#!/bin/sh

echo "=== XiaoAi MQTT 服务调试脚本 ==="
echo "当前时间: $(date)"
echo ""

echo "1. 检查Lua解释器:"
which lua
lua -v
echo ""

echo "2. 检查Lua脚本权限:"
ls -la /etc/xiaoai-mqtt/mqtt_client.lua
echo ""

echo "3. 尝试直接运行Lua脚本（5秒超时）:"
timeout 5 /usr/bin/lua /etc/xiaoai-mqtt/mqtt_client.lua 2>&1
echo "退出代码: $?"
echo ""

echo "4. 检查日志文件:"
ls -la /var/log/xiaoai-mqtt.log 2>/dev/null || echo "日志文件不存在"
echo ""

echo "5. 检查状态文件:"
ls -la /var/run/xiaoai-mqtt.status 2>/dev/null || echo "状态文件不存在"
echo ""

echo "6. 检查PID文件:"
ls -la /var/run/xiaoai-mqtt.pid 2>/dev/null || echo "PID文件不存在"
echo ""

echo "7. 检查进程是否在运行:"
pgrep -f "lua /etc/xiaoai-mqtt/mqtt_client.lua" && echo "进程正在运行" || echo "进程未运行"
echo ""

echo "8. 检查procd服务状态:"
service xiaoai-mqtt status 2>&1
echo ""

echo "9. 检查系统日志中的相关条目:"
logread | grep xiaoai-mqtt | tail -20
echo ""

echo "=== 调试完成 ==="
