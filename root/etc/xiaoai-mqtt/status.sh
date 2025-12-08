#!/bin/sh

STATUS_FILE="/var/run/xiaoai-mqtt.status"
LOG_FILE="/var/log/xiaoai-mqtt.log"

get_service_status() {
    if pgrep -f "lua /etc/xiaoai-mqtt/mqtt_client.lua" >/dev/null; then
        echo "running"
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
    printf "%d|%s" \
        $(wc -l <$LOG_FILE 2>/dev/null) \
        $(ls -lh $LOG_FILE 2>/dev/null | awk '{print $5}')
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