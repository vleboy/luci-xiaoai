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
            return E('div', { class: 'cbi-section' }, [
                E('div', { class: 'cbi-value' }, [
                    E('label', { class: 'cbi-value-title' }, _('服务状态')),
                    E('div', { class: 'cbi-value-field', id: 'service_status' }, [
                        E('em', { class: 'spinning' }, _('获取中...'))
                    ])
                ]),
                E('div', { class: 'cbi-value' }, [
                    E('label', { class: 'cbi-value-title' }, _('MQTT连接')),
                    E('div', { class: 'cbi-value-field', id: 'mqtt_status' }, [
                        E('em', { class: 'spinning' }, _('获取中...'))
                    ])
                ]),
                E('div', { class: 'cbi-value' }, [
                    E('label', { class: 'cbi-value-title' }, _('最近操作')),
                    E('div', { class: 'cbi-value-field', id: 'last_action' }, [
                        E('em', { class: 'spinning' }, _('获取中...'))
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
        o.rmempty = false;

        o = s.option(form.Value, 'mqtt_port', _('端口'));
        o.datatype = 'port';
        o.rmempty = false;
        o.default = '9501';

        o = s.option(form.Value, 'mqtt_client_id', _('客户端ID'));
        o.placeholder = _('随机生成');
        o.rmempty = false;

        o = s.option(form.Value, 'mqtt_topic', _('订阅主题'));
        o.placeholder = 'default_topic';
        o.rmempty = false;

        // WOL配置
        s = m.section(form.NamedSection, 'wol', 'wol', _('网络唤醒设置'));
        s.anonymous = true;
        s.addremove = false;

        o = s.option(form.Value, 'mac', _('目标MAC地址'));
        o.placeholder = '00:11:22:33:44:55';
        o.rmempty = false;
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
        o.rmempty = false;

        o = s.option(form.Value, 'user', _('用户名'));
        o.placeholder = 'admin';
        o.rmempty = false;

        o = s.option(form.Value, 'pass', _('密码'));
        o.password = true;
        o.rmempty = false;

        o = s.option(form.DynamicList, 'off_msgs', _('关机指令'));
        o.placeholder = 'off';
        o.rmempty = true;

        // 服务控制
        s = m.section(form.NamedSection, 'main', 'service', _('服务控制'));
        s.anonymous = true;
        s.addremove = false;

        o = s.option(form.Flag, 'enabled', _('启用服务'));
        o.default = '0';
        o.rmempty = false;

        // 状态更新
        poll.add(function() {
            return L.Request.get('/cgi-bin/luci/admin/services/xiaoai-mqtt/status').then(function(xhr) {
                var status = JSON.parse(xhr.responseText);
                var serviceStatus = document.getElementById('service_status');
                var mqttStatus = document.getElementById('mqtt_status');
                var lastAction = document.getElementById('last_action');

                if (serviceStatus) serviceStatus.textContent = status.service === 'running' ? _('运行中') : _('已停止');
                if (mqttStatus) mqttStatus.textContent = status.mqtt === 'connected' ? _('已连接') : _('未连接');
                if (lastAction) lastAction.textContent = status.last_action;
            });
        });

        return m.render();
    }
});