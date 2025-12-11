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
                ]),
                E('div', { class: 'service-controls', style: 'margin-top: 20px;' }, [
                    E('h4', { style: 'margin-bottom: 10px;' }, _('服务控制')),
                    E('div', { class: 'control-buttons' }, [
                        E('button', {
                            id: 'start_service_btn',
                            class: 'cbi-button cbi-button-action',
                            style: 'margin-right: 10px;'
                        }, _('启动服务')),
                        E('button', {
                            id: 'stop_service_btn',
                            class: 'cbi-button cbi-button-negative',
                            style: 'margin-right: 10px;'
                        }, _('停止服务')),
                        E('button', {
                            id: 'restart_service_btn',
                            class: 'cbi-button cbi-button-reset'
                        }, _('重启服务'))
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

        // 状态更新函数
        function updateStatus() {
            var url = '/cgi-bin/luci/admin/services/xiaoai-mqtt/status';
            var timestamp = new Date().getTime();
            var cacheBusterUrl = url + '?_=' + timestamp;
            
            L.Request.get(cacheBusterUrl).then(function(xhr) {
                try {
                    var status = JSON.parse(xhr.responseText);
                    
                    // 更新服务状态
                    updateElementStatus('service_status', function() {
                        var statusText = status.service === 'running' ? _('运行中') : _('已停止');
                        var statusClass = status.service === 'running' ? 'running' : 'stopped';
                        return { text: statusText, className: statusClass };
                    });
                    
                    // 更新MQTT状态
                    updateElementStatus('mqtt_status', function() {
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
                            case 'initializing':
                                statusText = _('初始化中...');
                                statusClass = 'status-connecting';
                                break;
                            default:
                                statusText = _('未连接');
                                statusClass = 'status-disconnected';
                        }
                        return { text: statusText, className: statusClass };
                    });
                    
                    // 更新最近操作
                    updateElementStatus('last_action', function() {
                        return { text: status.last_action || _('无'), className: '' };
                    });
                    
                    // 更新日志统计
                    updateElementStatus('log_stats', function() {
                        if (status.log_stats) {
                            var stats = status.log_stats.split('|');
                            if (stats.length >= 2) {
                                var lines = parseInt(stats[0]) || 0;
                                var size = stats[1] || '0B';
                                return { text: lines + ' 行 | ' + size, className: '' };
                            }
                        }
                        return { text: _('无日志'), className: '' };
                    });
                    
                    // 更新MQTT控制按钮
                    var mqttControlBtn = document.getElementById('mqtt_control_btn');
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
                        } else if (status.mqtt === 'connecting' || status.mqtt === 'reconnecting' || status.mqtt === 'initializing') {
                            mqttControlBtn.textContent = _('连接中...');
                            mqttControlBtn.disabled = true;
                            mqttControlBtn.className = 'cbi-button cbi-button-reset';
                        } else {
                            mqttControlBtn.textContent = _('连接');
                            mqttControlBtn.disabled = false;
                            mqttControlBtn.className = 'cbi-button cbi-button-action';
                        }
                    }
                    
                    // 更新服务控制按钮状态
                    var startBtn = document.getElementById('start_service_btn');
                    var stopBtn = document.getElementById('stop_service_btn');
                    var restartBtn = document.getElementById('restart_service_btn');
                    
                    if (startBtn) {
                        startBtn.disabled = status.service === 'running';
                        startBtn.className = status.service === 'running' ? 'cbi-button cbi-button-reset' : 'cbi-button cbi-button-action';
                    }
                    
                    if (stopBtn) {
                        stopBtn.disabled = status.service !== 'running';
                        stopBtn.className = status.service !== 'running' ? 'cbi-button cbi-button-reset' : 'cbi-button cbi-button-negative';
                    }
                    
                    if (restartBtn) {
                        restartBtn.disabled = status.service !== 'running';
                        restartBtn.className = status.service !== 'running' ? 'cbi-button cbi-button-reset' : 'cbi-button cbi-button-reset';
                    }
                    
                } catch (e) {
                    console.error('解析状态响应失败:', e);
                    // 显示解析错误
                    showErrorStatus('service_status', _('解析失败'));
                    showErrorStatus('mqtt_status', _('解析失败'));
                    showErrorStatus('last_action', _('解析失败'));
                    showErrorStatus('log_stats', _('解析失败'));
                }
                
                // 3秒后再次更新
                setTimeout(updateStatus, 3000);
                
            }).catch(function(err) {
                console.error('获取状态失败:', err);
                
                // 显示错误状态
                showErrorStatus('service_status', _('获取失败'));
                showErrorStatus('mqtt_status', _('获取失败'));
                showErrorStatus('last_action', _('获取失败'));
                showErrorStatus('log_stats', _('获取失败'));
                
                // 5秒后重试
                setTimeout(updateStatus, 5000);
            });
        }
        
        // 辅助函数：更新元素状态
        function updateElementStatus(elementId, getStatusInfo) {
            var element = document.getElementById(elementId);
            if (element) {
                // 移除spinning元素
                var spinning = element.querySelector('.spinning');
                if (spinning) {
                    element.removeChild(spinning);
                }
                
                // 清除现有内容
                while (element.firstChild) {
                    element.removeChild(element.firstChild);
                }
                
                // 获取状态信息
                var statusInfo = getStatusInfo();
                if (statusInfo) {
                    var statusSpan = document.createElement('span');
                    statusSpan.textContent = statusInfo.text;
                    if (statusInfo.className) {
                        statusSpan.className = statusInfo.className;
                    }
                    element.appendChild(statusSpan);
                }
            }
        }
        
        // 辅助函数：显示错误状态
        function showErrorStatus(elementId, errorText) {
            var element = document.getElementById(elementId);
            if (element) {
                // 移除spinning元素
                var spinning = element.querySelector('.spinning');
                if (spinning) {
                    element.removeChild(spinning);
                }
                
                // 清除现有内容
                while (element.firstChild) {
                    element.removeChild(element.firstChild);
                }
                
                // 创建错误文本
                var errorSpan = document.createElement('span');
                errorSpan.textContent = errorText;
                errorSpan.className = 'status-disconnected';
                element.appendChild(errorSpan);
            }
        }
        
        // 初始化状态更新和按钮事件处理
        function initStatusUpdate() {
            // 立即开始更新状态
            updateStatus();
            
            // MQTT控制按钮事件处理
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

            // 服务控制按钮事件处理
            function setupServiceControlButton(buttonId, endpoint, successMessage) {
                var button = document.getElementById(buttonId);
                if (button) {
                    button.addEventListener('click', function() {
                        var btn = this;
                        var originalText = btn.textContent;
                        
                        // 禁用按钮并显示加载状态
                        btn.disabled = true;
                        btn.textContent = _('处理中...');
                        btn.className = 'cbi-button cbi-button-reset';
                        
                        // 发送服务控制请求
                        L.Request.post('/cgi-bin/luci/admin/services/xiaoai-mqtt/' + endpoint, {
                            json: true
                        }).then(function(xhr) {
                            var response = JSON.parse(xhr.responseText);
                            if (response.success) {
                                btn.textContent = successMessage || _('操作成功');
                                btn.className = 'cbi-button cbi-button-positive';
                                // 立即更新状态
                                setTimeout(updateStatus, 500);
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
            }

            // 设置服务控制按钮
            setupServiceControlButton('start_service_btn', 'start', _('启动成功'));
            setupServiceControlButton('stop_service_btn', 'stop', _('停止成功'));
            setupServiceControlButton('restart_service_btn', 'restart', _('重启成功'));
        }

        return m.render().then(function(node) {
            // 启动状态更新循环
            setTimeout(initStatusUpdate, 500);
            return node;
        });
    }
});
