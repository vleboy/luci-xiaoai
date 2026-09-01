# luci-app-xiaoai-mqtt 使用与编译指南

## 项目概述

这是一个用于 OpenWrt/ImmortalWrt 的 LuCI 应用程序，通过 MQTT 订阅控制小爱（巴法云）设备：

- 收到触发消息后执行 **WOL 网络唤醒**（etherwake）
- 收到触发消息后执行 **SMB 远程关机**（net rpc shutdown）
- Web 界面提供 MQTT 参数、WOL、关机配置与日志查看/下载

> 目标环境：ImmortalWrt 24.10 / x86_64（其他版本请在 SDK 中核实依赖包名）。

## 工作原理与 MQTT 认证说明

巴法云（bemfa.com）使用**私钥（key）作为 MQTT 的 client_id** 完成鉴权：

```sh
mosquitto_sub -h bemfa.com -p 9501 -t <主题> -i <巴法云私钥> -q 1 -v
```

连接时**不需要用户名/密码**（可留空或随意填写），因此本应用不提供 MQTT 账号密码配置项。
如需连接需要账号密码鉴权的其他 broker，请自行在 `root/etc/xiaoai-mqtt/mqtt_client.lua` 的
`start_mosquitto_sub()` 中追加 `-u/-P` 参数（注意使用 `shell_quote` 转义）。

## 目录结构

```
luci-app-xiaoai-mqtt/
├── Makefile              # 构建配置文件
├── htdocs/luci-static/resources/view/xiaoai-mqtt/
│   ├── index.js          # 前端 JS view（配置 + 状态 + 服务控制）
│   └── style.css         # 前端样式
├── luasrc/view/xiaoai-mqtt/
│   └── log.htm           # 日志页面模板
└── root/
    ├── etc/
    │   ├── config/xiaoai-mqtt          # UCI 配置文件
    │   ├── init.d/xiaoai-mqtt          # procd 启动脚本
    │   ├── uci-defaults/luci-xiaoai-mqtt  # 首次安装初始化
    │   └── xiaoai-mqtt/mqtt_client.lua # MQTT 守护进程（核心）
    └── usr/lib/lua/luci/controller/xiaoai-mqtt.lua  # LuCI 控制器
```

## 依赖项

- `luci-base`、`luci-lua-nixio`（提供 nixio 模块，守护进程必需）
- `mosquitto-client-nossl`（mosquitto_sub 客户端，本应用不使用 TLS）
- `etherwake`（WOL）
- `samba4-admin`（net rpc shutdown；请核实目标固件上 `net` 二进制的实际路径，
  代码默认调用 `/usr/bin/net`，若为 `/usr/sbin/net` 请修改 `mqtt_client.lua` 中 `execute_shutdown`）

## 本地编译方法（SDK）

### 1. 准备环境

```bash
sudo apt-get update
sudo apt-get install -y build-essential ccache fastjar file g++ gawk gettext git libelf-dev \
    libncurses5-dev libncursesw5-dev libssl-dev python3 python3-distutils python3-setuptools \
    unzip wget rsync subversion swig time xsltproc zlib1g-dev zstd tree
```

### 2. 下载 ImmortalWrt SDK

```bash
# 示例：x86/64 平台，24.10.0 版本（按需修改）
TARGET="x86/64"
VERSION="24.10.0"
TARGET_DASH=$(echo $TARGET | sed 's/\//-/')
SDK_BASE_URL="https://mirror.nju.edu.cn/immortalwrt/releases/$VERSION/targets/$TARGET/"
SDK_FILE=$(curl -s $SDK_BASE_URL | grep -oP "immortalwrt-sdk-.*?-$TARGET_DASH_gcc-.*?Linux-x86_64.tar.zst" | head -n 1)
wget "${SDK_BASE_URL}${SDK_FILE}" -O immortalwrt.tar.zst
mkdir immortalwrt
tar -I zstd -xvf immortalwrt.tar.zst -C immortalwrt --strip-components 1
```

### 3. 复制插件源码并编译

```bash
cd immortalwrt
./scripts/feeds update -a
./scripts/feeds install -a

mkdir -p package/luci-app-xiaoai-mqtt
rsync -av --exclude='.git' /path/to/luci-app-xiaoai-mqtt/ package/luci-app-xiaoai-mqtt/

cat >> .config << EOF
CONFIG_PACKAGE_luci-app-xiaoai-mqtt=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-lua-nixio=y
CONFIG_PACKAGE_mosquitto-client-nossl=y
CONFIG_PACKAGE_etherwake=y
CONFIG_PACKAGE_samba4-admin=y
EOF

make defconfig
make package/luci-app-xiaoai-mqtt/compile V=s -j$(nproc)

find bin/packages -name "luci-app-xiaoai-mqtt*.ipk"
```

> 提示：在 `make menuconfig` 中可核对 `mosquitto-client-nossl`、`samba4-admin` 的实际包名与
> `net` 二进制路径，不同版本可能略有差异。

## 安装与使用

```bash
# 上传并安装
scp luci-app-xiaoai-mqtt*.ipk root@路由器IP:/tmp/
ssh root@路由器IP "cd /tmp && opkg install luci-app-xiaoai-mqtt*.ipk"

# 访问界面
# http://路由器IP/cgi-bin/luci/admin/services/xiaoai-mqtt
```

### 配置项说明

| 配置 | 说明 |
|---|---|
| 服务器地址 | MQTT broker，默认 `bemfa.com` |
| 端口 | 默认 `9501` |
| 巴法云key（client_id） | 巴法云私钥，**即连接凭证** |
| 订阅主题 | 默认 `bemfa_public`，私有主题请改为自己的主题 |
| 目标MAC地址 | WOL 唤醒目标 |
| 唤醒网卡 | WOL 发送网卡，默认 `br-lan` |
| 触发消息 | 收到该 payload 即执行 WOL，默认 `on` |
| 目标IP/用户名/密码 | SMB 关机目标与凭据（凭据明文存于 UCI，请妥善保管） |
| 关机指令 | 收到该 payload 即执行关机，默认 `off` |

## 日志与状态

```bash
cat /var/log/xiaoai-mqtt.log          # 应用日志（Web 界面可查看/下载）
cat /var/run/xiaoai-mqtt.status      # 状态文件
/etc/init.d/xiaoai-mqtt status       # 服务状态
```

## 已知限制

- 消息轮询周期约 3 秒，WOL/关机触发存在约 3–6 秒延迟。
- SMB 关机密码明文存储在 UCI 配置文件中，请确保路由器文件系统安全。
- `net rpc shutdown` 依赖 samba4-admin 提供的 `net` 二进制，路径因固件而异。

## 故障排除

1. **服务起不来**：检查 `logread | grep xiaoai`；确认 `luci-lua-nixio` 已安装（`require "nixio"` 失败会直接退出）。
2. **收不到消息**：确认巴法云私钥与主题正确；订阅进程输出在 `/tmp/mosquitto_sub.out`。
3. **WOL 无效**：确认目标 MAC 与唤醒网卡正确，且目标与路由器在同一二层网络。
4. **日志页清空按钮 403**：多为 LuCI CSRF token 问题，确认页面表单包含隐藏 token 字段。
