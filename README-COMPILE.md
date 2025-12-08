# luci-app-xiaoai-mqtt 编译指南

## 项目概述

这是一个用于OpenWrt/ImmortalWrt的Luci应用程序，通过MQTT控制小爱设备。应用程序提供了Web界面来配置MQTT连接、WOL（网络唤醒）和SMB关机功能。

## 代码检查结果

我已经检查了代码，以下是关键发现：

### 项目结构
```
luci-app-xiaoai-mqtt/
├── Makefile              # 构建配置文件
├── htdocs/              # Web静态资源
│   └── luci-static/resources/view/xiaoai-mqtt/
│       ├── index.js     # 前端JavaScript
│       └── style.css    # 前端样式
├── luasrc/              # Lua源代码
│   └── view/xiaoai-mqtt/
│       ├── log.htm      # 日志页面模板
│       └── status.htm   # 状态页面模板
├── root/                # 系统文件
│   ├── etc/
│   │   ├── config/xiaoai-mqtt          # 配置文件
│   │   ├── init.d/xiaoai-mqtt          # 启动脚本
│   │   └── xiaoai-mqtt/
│   │       ├── mqtt_client.lua         # 主MQTT客户端
│   │       └── status.sh               # 状态检查脚本
│   └── usr/lib/lua/luci/
│       ├── controller/xiaoai-mqtt.lua  # 控制器
│       └── model/cbi/xiaoai-mqtt/
│           ├── basic.lua               # 基本配置页面
│           └── log.lua                 # 日志页面
└── .github/workflows/   # GitHub Actions工作流
    ├── build-immortalwrt.yml  # 主要编译工作流
    └── build.yml              # 简单检查工作流
```

### 代码质量评估
1. **结构良好**：项目遵循标准的OpenWrt/Luci应用程序结构
2. **功能完整**：实现了MQTT客户端、WOL、SMB关机等核心功能
3. **错误处理**：代码中包含适当的错误处理和日志记录
4. **安全性**：配置文件使用适当权限，密码等敏感信息有基本保护

### 依赖项
- Lua运行时环境
- mosquitto-client-ssl (MQTT客户端)
- LuCI框架

## 编译方法

### 方法1：使用GitHub Actions（推荐）

1. 访问GitHub仓库的Actions页面
2. 选择"编译 ImmortalWrt 插件 (luci-app-xiaoai-mqtt)"工作流
3. 点击"Run workflow"
4. 配置参数：
   - **目标平台/架构**：例如 `x86/64` (默认)
   - **固件版本**：例如 `24.10.0` (默认)
5. 等待编译完成，下载生成的IPK文件

### 方法2：本地编译

#### 步骤1：准备环境
```bash
# 安装依赖
sudo apt-get update
sudo apt-get install -y build-essential ccache ecj fastjar file g++ gawk \
gettext git java-propose-classpath libelf-dev libncurses5-dev \
libncursesw5-dev libssl-dev python3 python3-distutils python3-setuptools \
unzip wget rsync subversion swig time xsltproc zlib1g-dev tree zstd
```

#### 步骤2：下载ImmortalWrt SDK
```bash
# 示例：x86/64平台，24.10.0版本
TARGET="x86/64"
VERSION="24.10.0"
TARGET_DASH=$(echo $TARGET | sed 's/\//-/')
SDK_BASE_URL="https://mirror.nju.edu.cn/immortalwrt/releases/$VERSION/targets/$TARGET/"
SDK_FILE=$(curl -s $SDK_BASE_URL | grep -oP "immortalwrt-sdk-.*?-$TARGET_DASH_gcc-.*?Linux-x86_64.tar.zst" | head -n 1)
SDK_URL="${SDK_BASE_URL}${SDK_FILE}"
wget $SDK_URL -O immortalwrt.tar.zst
mkdir immortalwrt
tar -I zstd -xvf immortalwrt.tar.zst -C immortalwrt --strip-components 1
```

#### 步骤3：复制插件源码
```bash
cd immortalwrt/package
mkdir -p luci-app-xiaoai-mqtt
# 复制所有文件，排除 immortalwrt 和 .git 目录
cd /path/to/luci-app-xiaoai-mqtt
rsync -av --exclude='immortalwrt' --exclude='.git' . ../../package/luci-app-xiaoai-mqtt/
# 确保在正确的目录
cd ../../package/luci-app-xiaoai-mqtt
# 再次确认移除 .git 目录（如果存在）
rm -rf .git 2>/dev/null || true
```

#### 步骤4：编译
```bash
cd immortalwrt
./scripts/feeds update -a
./scripts/feeds install -a

# 根据目标平台生成配置
TARGET="x86/64"  # 修改为您需要的目标平台
ARCH=$(echo "$TARGET" | cut -d'/' -f1)
SUBTARGET=$(echo "$TARGET" | cut -d'/' -f2)

# 配置
cat > .config << EOF
CONFIG_TARGET_${ARCH}=y
CONFIG_TARGET_${ARCH}_${SUBTARGET}=y
CONFIG_TARGET_${ARCH}_${SUBTARGET}_DEVICE_generic=y
CONFIG_PACKAGE_luci-app-xiaoai-mqtt=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-lib-base=y
CONFIG_PACKAGE_luci-lib-ipkg=y
CONFIG_PACKAGE_luci-theme-bootstrap=y
CONFIG_PACKAGE_mosquitto-client-ssl=y
EOF

make defconfig
make package/luci-app-xiaoai-mqtt/compile V=s
```

#### 步骤5：获取IPK文件
```bash
find bin/packages -name "luci-app-xiaoai-mqtt*.ipk"
```

## 安装和使用

### 安装IPK
```bash
# 上传IPK到路由器
scp luci-app-xiaoai-mqtt*.ipk root@路由器IP:/tmp/

# SSH登录路由器
ssh root@路由器IP

# 安装
cd /tmp
opkg update
opkg install luci-app-xiaoai-mqtt*.ipk
```

### 访问界面
1. 打开浏览器访问 `http://路由器IP/cgi-bin/luci/admin/services/xiaoai-mqtt`
2. 配置MQTT连接参数
3. 配置WOL和SMB关机设置
4. 启动服务

## 故障排除

### 常见问题
1. **编译失败**：检查SDK版本是否匹配目标平台
2. **依赖缺失**：确保所有feeds已正确更新
3. **安装失败**：检查路由器架构是否与IPK匹配

### 日志查看
```bash
# 查看应用程序日志
cat /var/log/xiaoai-mqtt.log

# 查看服务状态
/etc/init.d/xiaoai-mqtt status
```

## 基于的编译仓库

本编译配置基于 [vleboy/compile-ipk_ImmortalWrt](https://github.com/vleboy/compile-ipk_ImmortalWrt) 仓库，该仓库提供了完整的ImmortalWrt插件编译工作流。

## 支持的目标平台

- x86/64 (默认)
- ramips/mt7621
- 其他ImmortalWrt支持的平台

要编译其他平台，请在GitHub Actions中修改`target`参数。
