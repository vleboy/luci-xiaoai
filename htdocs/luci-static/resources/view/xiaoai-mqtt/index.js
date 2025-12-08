'use strict';
'require view';
'require form';
'require uci';
'require fs';
'require ui';
'require poll';

return view.extend({
    render: function() {
        var m, s, o;

        m = new form.Map('xiaoai-mqtt', _('XiaoAi MQTT'), _('配置MQTT服务参数和设备控制选项'));

        // 服务状态显示
        s = m.section(form.NamedSection, 'status', 'status', _('服务状态'));
        s.anonymous = true;
        s.addremove = false;
        s.render = L.bind(function(view, section_id) {
            return E('div', { class: 'service-status-card' }, [
                E('h3', { class: 'cbi-section-title' }, _('服务状态')),
                E('div', { class: 'status-grid' }, [
                    E('div', { class: 'status-item' }, [
                        E('div', { class: 'label' }, _('服务状态')),
                        E('div', { class: 'value', id: 'service_status' }, [
                            E('em', { class: 'spinning' }, _('获取中...'))
                        ])
                    ]),
                    E('div', { class: 'status-item' }, [
                        E('div', { class: 'label' }, _('MQTT连接')),
                        E('div', { class: 'cbi-value-field', id: 'mqtt_status_container' }, [
                            E('span', { id: 'mqtt_status' }, [
                                E('em', { class: 'spinning' }, _('获取中...'))
                            ]),
                            E('button', {
                                id: 'mqtt_control_btn',
                                class: 'cbi-button cbi-button-action',
                                style: 'margin-left: 10px; display: none;'
                            }, _('重新连接'))
                        ])
                    ]),
                    E('div', { class: 'status-item' }, [
                        E('div', { class: 'label' }, _('最近操作')),
                        E('div', { class: 'value', id: 'last_action' }, [
                            E('em', { class: 'spinning' }, _('获取中...'))
                        ])
                    ]),
                    E('div', { class: 'status-item' }, [
                        E('div', { class: 'label' }, _('日志统计')),
                        E('div', { class: 'value', id: 'log_stats' }, [
                            E('em', { class: 'spinning' }, _('获取中...'))
                        ])
                    ])
                ])
            ]);
        }, this);

        // MQTT配置
        s = m.section(form.NamedSection, 'mqtt', 'mqtt', _('MQTT参数'));
        s.anonymous = true;
        s.addremove = false;

        o = s.option(form.Value, 'mqtt_broker', _('服务器地址'));
        o.placeholder = 'bemfa.com';
        o.rmempty = true;

        o = s.option(form.Value, 'mqtt_port', _('端口'));
        o.datatype = 'port';
        o.rmempty = true;
        o.default = '9501';

        o = s.option(form.Value, 'mqtt_client_id', _('客户端ID'));
        o.placeholder = _('随机生成');
        o.rmempty = true;

        o = s.option(form.Value, 'mqtt_topic', _('订阅主题'));
        o.placeholder = 'default_topic';
        o.rmempty = true;

        // WOL配置
        s = m.section(form.NamedSection, 'wol', 'wol', _('网络唤醒设置'));
        s.anonymous = true;
        s.addremove = false;

        o = s.option(form.Value, 'mac', _('目标MAC地址'));
        o.placeholder = '00:11:22:33:44:55';
        o.rmempty = true;
        o.datatype = 'macaddr';

        o = s.option(form.DynamicList, 'on_msgs', _('触发消息'));
        o.placeholder = 'on';
        o.rmempty = true;

        // 关机配置
        s = m.section(form.NamedSection, 'shutdown', 'shutdown', _('远程关机设置'));
        s.anonymous = true;
        s.addremove = false;

        o = s.option(form.Value, 'ip', _('目标IP地址'));
        o.datatype = 'ip4addr';
        o.rmempty = true;

        o = s.option(form.Value, 'user', _('用户名'));
        o.placeholder = 'admin';
        o.rmempty = true;

        o = s.option(form.Value, 'pass', _('密码'));
        o.password = true;
        o.rmempty = true;

        o = s.option(form.DynamicList, 'off_msgs', _('关机指令'));
        o.placeholder = 'off';
        o.rmempty = true;

        // 服务控制
        s = m.section(form.NamedSection, 'main', 'service', _('服务控制'));
        s.anonymous = true;
        s.addremove = false;

        o = s.option(form.Flag, 'enabled', _('启用服务'));
        o.default = '0';
        o.rmempty = true;

        // 状态更新（优化版）
        var lastStatus = {};
        var updateInterval = 3000; // 初始3秒
        var consecutiveErrors = 0;
        var maxUpdateInterval = 30000; // 最大30秒
        
        function updateStatus() {
            return L.Request.get('/cgi-bin/luci/admin/services/xiaoai-mqtt/status').then(function(xhr) {
                consecutiveErrors = 0;
                var status = JSON.parse(xhr.responseText);
                
                // 检查状态是否真的改变了
                var hasChanged = false;
                if (lastStatus.service !== status.service || 
                    lastStatus.mqtt !== status.mqtt ||
                    lastStatus.last_action !== status.last_action ||
                    lastStatus.log_stats !== status.log_stats) {
                    hasChanged = true;
                    lastStatus = Object.assign({}, status);
                }
                
                // 如果没有变化且不是第一次更新，可以延长更新间隔
                if (!hasChanged && updateInterval < maxUpdateInterval) {
                    updateInterval = Math.min(updateInterval * 1.5, maxUpdateInterval);
                } else if (hasChanged) {
                    updateInterval = 3000; // 重置为3秒
                }
                
                var serviceStatus = document.getElementById('service_status');
                var mqttStatus = document.getElementById('mqtt_status');
                var lastAction = document.getElementById('last_action');
                var logStats = document.getElementById('log_stats');
                var mqttControlBtn = document.getElementById('mqtt_control_btn');

                // 更新服务状态
                if (serviceStatus) {
                    serviceStatus.textContent = status.service === 'running' ? _('运行中') : _('已停止');
                    serviceStatus.className = 'value ' + (status.service === 'running' ? 'running' : 'stopped');
                }
                
                // 更新MQTT状态显示
                if (mqttStatus) {
                    var statusText = '';
                    var statusClass = '';
                    switch(status.mqtt) {
                        case 'connected':
                            statusText = _('已连接');
                            statusClass = 'status-connected';
                            break;
                        case 'connecting':
                            statusText = _('连接中...');
                            statusClass = 'status-connecting';
                            break;
                        case 'reconnecting':
                            statusText = _('重新连接中...');
                            statusClass = 'status-reconnecting';
                            break;
                        default:
                            statusText = _('未连接');
                            statusClass = 'status-disconnected';
                    }
                    mqttStatus.textContent = statusText;
                    mqttStatus.className = statusClass;
                }
                
                // 更新日志统计
                if (logStats && status.log_stats) {
                    var stats = status.log_stats.split('|');
                    if (stats.length >= 2) {
                        var lines = parseInt(stats[0]) || 0;
                        var size = stats[1] || '0B';
                        logStats.textContent = lines + ' 行 | ' + size;
                    }
                }
                
                // 更新最近操作
                if (lastAction) {
                    lastAction.textContent = status.last_action || _('无');
                }
                
                // 更新控制按钮
                if (mqttControlBtn) {
                    mqttControlBtn.style.display = 'inline-block';
                    
                    if (status.service !== 'running') {
                        mqttControlBtn.textContent = _('服务未运行');
                        mqttControlBtn.disabled = true;
                        mqttControlBtn.className = 'cbi-button cbi-button-reset';
                    } else if (status.mqtt === 'connected') {
                        mqttControlBtn.textContent = _('重新连接');
                        mqttControlBtn.disabled = false;
                        mqttControlBtn.className = 'cbi-button cbi-button-action';
                    } else if (status.mqtt === 'connecting' || status.mqtt === 'reconnecting') {
                        mqttControlBtn.textContent = _('连接中...');
                        mqttControlBtn.disabled = true;
                        mqttControlBtn.className = 'cbi-button cbi-button-reset';
                    } else {
                        mqttControlBtn.textContent = _('连接');
                        mqttControlBtn.disabled = false;
                        mqttControlBtn.className = 'cbi-button cbi-button-action';
                    }
                }
                
                // 安排下一次更新
                setTimeout(updateStatus, updateInterval);
                
            }).catch(function(err) {
                consecutiveErrors++;
                // 错误时增加更新间隔
                updateInterval = Math.min(updateInterval * 2, maxUpdateInterval);
                
                // 显示错误状态
                var mqttStatus = document.getElementById('mqtt_status');
                if (mqttStatus) {
                    mqttStatus.textContent = _('获取状态失败');
                    mqttStatus.className = 'status-disconnected';
                }
                
                // 安排下一次更新
                setTimeout(updateStatus, updateInterval);
            });
        }
        
        // 初始状态更新
        setTimeout(updateStatus, 1000);
        
        // 添加按钮点击事件处理
        document.addEventListener('DOMContentLoaded', function() {
            var mqttControlBtn = document.getElementById('mqtt_control_btn');
            if (mqttControlBtn) {
                mqttControlBtn.addEventListener('click', function() {
                    var btn = this;
                    var originalText = btn.textContent;
                    
                    // 禁用按钮并显示加载状态
                    btn.disabled = true;
                    btn.textContent = _('处理中...');
                    btn.className = 'cbi-button cbi-button-reset';
                    
                    // 发送重新连接请求
                    L.Request.post('/cgi-bin/luci/admin/services/xiaoai-mqtt/reconnect', {
                        json: true
                    }).then(function(xhr) {
                        var response = JSON.parse(xhr.responseText);
                        if (response.success) {
                            btn.textContent = _('已发送重新连接请求');
                            // 3秒后恢复按钮状态
                            setTimeout(function() {
                                // 按钮状态会在下一次轮询时更新
                            }, 3000);
                        } else {
                            btn.textContent = _('失败: ') + response.message;
                            btn.className = 'cbi-button cbi-button-negative';
                            // 5秒后恢复按钮状态
                            setTimeout(function() {
                                // 按钮状态会在下一次轮询时更新
                            }, 5000);
                        }
                    }).catch(function(err) {
                        btn.textContent = _('请求失败');
                        btn.className = 'cbi-button cbi-button-negative';
                        // 5秒后恢复按钮状态
                        setTimeout(function() {
                            // 按钮状态会在下一次轮询时更新
                        }, 5000);
                    });
                });
            }
        });

        return m.render();
    }
});
