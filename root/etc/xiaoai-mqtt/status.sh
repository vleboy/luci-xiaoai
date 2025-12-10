#!/bin/sh

STATUS_FILE="/var/run/xiaoai-mqtt.status"
LOG_FILE="/var/log/xiaoai-mqtt.log"

get_service_status() {
    local pid_file="/var/run/xiaoai-mqtt.pid"
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "running"
        else
            echo "stopped"
        fi
    else
        echo "stopped"
    fi
}

get_mqtt_status() {
    [ -f $STATUS_FILE ] && {
        awk -F'=' '/mqtt_connection/{print $2}' $STATUS_FILE
    } || echo "disconnected"
}

get_last_action() {
    [ -f $STATUS_FILE ] && {
        awk -F'=' '/last_action/{print $2}' $STATUS_FILE | tail -n1
    } || echo "N/A"
}

get_log_stats() {
    local line_count=0
    local file_size="0B"
    if [ -f "$LOG_FILE" ]; then
        line_count=$(wc -l <"$LOG_FILE" 2>/dev/null)
        file_size=$(ls -lh "$LOG_FILE" 2>/dev/null | awk '{print $5}')
    fi
    printf "%d|%s" "$line_count" "$file_size"
}

case $1 in
    full)
        echo "service_status=$(get_service_status)"
        echo "mqtt_connection=$(get_mqtt_status)"
        echo "last_action=$(get_last_action)"
        echo "log_stats=$(get_log_stats)"
        ;;
    *)
        get_service_status
        ;;
esac
