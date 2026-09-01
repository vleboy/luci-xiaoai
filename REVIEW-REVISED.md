# luci-app-xiaoai-mqtt 代码审查报告（修订版）

> **审查对象**：本项目全部 15 个文件（Makefile、GitHub 工作流、LuCI 控制器/CBI/JS view、Lua 守护进程、init.d、UCI 配置等）
> **目标环境**：ImmortalWrt 24.10 / x86_64（用户确认）
> **状态**：审查完成，修复计划已定稿；**暂未修改任何代码**（用户决定"仅保留计划"）
> **文档定位**：本报告为初版审查 + 交叉复核后的修订版，编号与初版不同，含"修订记录"对照。

---

## 0. 修订记录（相对初版审查）

| 原编号 | 修订编号 | 变更 |
|---|---|---|
| A1 | S3 | 保留，验证成立（luci2 `request.js` 的 `json:true` 行为） |
| A2 | S4 | 保留，验证成立（pgrep 只排除自身、不排除父 shell） |
| A3 | S5 | 保留，机制表述微调（损失发生在 payload 被 NUL 破坏 / 读窗全 NUL，而非"topic 匹配失败"） |
| A4 | S6 | 保留 |
| A5 | S7 | **方向修订**：按用户决定"私钥即 client_id、无需账号密码"，改为**删除** `mqtt_user/mqtt_pass` 字段，而非实现 `-u/-P` |
| A6 | S8 | 保留（严重度按"高"亦可，见正文） |
| B1 | H1 | 保留 |
| B2 | H2 | 保留 |
| B3 | M1 | 保留，补充 `status.sh` 亦为死代码 |
| B4 | M2 | 保留为防御性建议（LuCI Web 环境下 nixio 通常已是全局，500 概率低） |
| B5 | H3 + **S2** | 拆分：sub 命令注入→H3；**`execute_shutdown` 注入原遗漏→新增 S2** |
| B6 | H4 | 保留 |
| C1 | M3 | 保留 |
| C2 | M4 | 保留 |
| C3 | M5 | 保留 |
| C4 | M6 | 保留 |
| C5 | H6 | **修订**：`+lua` 不含 nixio（须补 `+luci-lua-nixio`）；`mosquitto-client` 包名未验证；samba4-admin 的 `net` 路径未验证 |
| C6 | M7 | 保留前半（类型不一致），"保存追加多余段"的后果改为"未验证" |
| C7 | M8 | 保留 |
| C8 | M9 | **修订**：按用户"仅本地编译"决定，改为**删除 workflow** 而非升级 checkout@v4 |
| C9 | M10 | 保留 |
| — | **S1** | **新增（原遗漏，最致命）**：`%d` 格式化 UCI 字符串崩溃，服务永远连不上 MQTT |
| — | **H5** | **新增（原遗漏）**：reconnect 端点发 SIGHUP 给 mosquitto_sub，默认行为是退出而非重连 |
| — | **H7** | **新增（原遗漏，需验证）**：log.htm 普通 form POST 的 CSRF 问题 |
| — | M11 | 新增：JS 按钮失败路径不恢复 disabled/文案 |
| — | M12 | 新增：`write_log` 每次 `io.open/close`，高频下 IO 开销大 |
| — | M13 | 新增：`get_status` 每次遍历日志统计行数，应改用 `wc -l` |

---

## 1. 结论摘要

**当前代码在目标环境上"能安装、跑不起来"**：最致命的不是任何已列问题，而是 **S1（`%d` 崩溃）——mosquitto_sub 从未成功启动过**。修完 S1–S8 前，其余问题没有意义。

- 🔴 严重 8 项（S1–S8）：核心功能不可用 / 安全漏洞
- 🟠 高 7 项（H1–H7）：功能错误或部署风险
- 🟡 中低 13 项（M1–M13）
- 🟢 清理 5 项（L1–L5）

---

## 2. 问题清单

### 2.1 🔴 严重（S1–S8）

| 编号 | 位置 | 问题 | 影响 | 修复要点 |
|---|---|---|---|---|
| **S1** | `root/etc/xiaoai-mqtt/mqtt_client.lua:332-340` | `string.format("... -p %d ...", config.mqtt_port)`——`uci:get_all()` 返回值永远是字符串（`"9501"`），Lua 5.1 `%d` 遇字符串抛 `bad argument #2 to 'format' (number expected, got string)`；被主循环 `pcall` 捕获后无限重试 | **mosquitto_sub 从未启动，服务形同虚设**（最大 bug） | `tonumber()` + 1–65535 校验，无效则明确报错返回 |
| **S2** | `mqtt_client.lua:276` | `execute_shutdown` 把 `ip/user/pass` 未转义拼入 `/usr/bin/net rpc shutdown -I %s -U '%s%%%s'` | 密码含 `'` 直接破坏命令、含 shell 元字符可**命令注入（root）**；输入来自 Web 配置 | 全部 `%q` 转义；`-U %q` 传 `user%pass` 组合串 |
| **S3** | `htdocs/.../index.js:335/338、378/381` | `L.Request.post(url, {json:true})` 的 Promise **resolve 的是已解析的 JSON 对象**（luci2 `request.js`：`if (data.json) resolve(JSON.parse(xhr.responseText)) else resolve(xhr)`），回调里再 `JSON.parse(xhr.responseText)` → `responseText` 为 `undefined` → SyntaxError → 走 catch | 重连/启动/停止/重启 4 个按钮**永远显示"请求失败"**（操作其实已执行）；同文件 GET 轮询不带 json 所以正常 | 保留 `{json:true}`、回调直接用 `response`（去掉 `JSON.parse`），或去掉 `json:true` 保持 `xhr` 解析，二者取一并加兜底 |
| **S4** | `root/usr/lib/lua/luci/controller/xiaoai-mqtt.lua:26/100/196/247` | `luci.sys.call("pgrep -f 'lua /etc/xiaoai-mqtt/mqtt_client.lua' ...")` 经 `sh -c` 执行；sh 自身 cmdline 含模式串，而 pgrep（busybox/procps）**只排除自身、不排除父 shell** → 恒匹配 | 服务状态**永远"运行中"**；"启动服务"永远走进"服务已经在运行"分支，**已停止的服务无法从 UI 启动** | `pgrep -f '[l]ua /etc/...'`（方括号技巧）；更稳妥：去掉 pgrep 回退，只依赖 procd pidfile + `/proc/<pid>` 检查 |
| **S5** | `mqtt_client.lua:333/407/427/468` | mosquitto_sub 以 `> file`（非 append）持有 fd；Lua 端 `fs.writefile(SUB_OUTPUT_FILE, "")` 截断后子进程偏移不变 → 下次写入落在文件中间产生 **NUL 空洞**；`content:sub(1,8192)` 只取前 8KB 却清空整文件；`processed_count > 50` 直接丢弃 | NUL 破坏 payload 导致触发词比较失败；累计写入超 8KB 后整个读窗全是 NUL、**所有 WOL/关机指令静默失效直到重启** | sub 改 `>>` 追加写 + Lua 持久化读偏移（读到 EOF 再更新）；超阈值才截断并重置偏移（append 的 O_APPEND 保证截断安全）；不丢弃消息、留到下一轮 |
| **S6** | `mqtt_client.lua:410-417` | "Connection refused"/"Not authorized" 时 `os.exit(1)` **只杀 Lua 进程，不杀 sub**（sub 是 sh 后台子进程，reparent 到 init）；procd respawn 新实例只删 pidfile/output 文件、不杀旧 sub | **孤儿 sub 累积 + 同 client_id 双 sub 会话互相抢占（flapping）**，孤儿 sub 仍能触发 WOL/关机；respawn 5 次后服务永久停止 | 启动时先按 pidfile + pgrep 清理残留 sub；"Connection refused" 不再 `os.exit`（进程死亡+退避重启已覆盖）；"Not authorized" 退出前先杀 sub |
| **S7** | `mqtt_client.lua:332-340`、`root/etc/config/xiaoai-mqtt:6-7` | `mqtt_user/mqtt_pass` 配置项存在但**从未被任何代码读取**，sub 命令无 `-u/-P`；L342 的 `cmd:gsub(" -P '%S+'", "")` 是空操作（命令里没有 -P） | 配置项误导；对需要鉴权的通用 broker 必然订阅失败 | **按用户决定：删除这两个配置字段与 UI 引用**（巴法云私钥即 client_id，无需账号密码）；README 注明 |
| **S8** | `mqtt_client.lua:276-278` | `execute_shutdown` 把含 `-U 'user%pass'` 的**完整命令写入日志**，日志可在 Web 界面 tail 与下载 | **SMB 密码明文泄露**（默认只有 root 能进 LuCI，实际泄露面为多管理员/日志外传场景，故严重度亦可按"高"） | 日志一律脱敏：任何含密码的命令记录为 `******`，不落明文 |

### 2.2 🟠 高（H1–H7）

| 编号 | 位置 | 问题 | 修复要点 |
|---|---|---|---|
| H1 | `mqtt_client.lua:267-279` | 自定义 `os.capture` 忽略退出码、返回输出字符串；**空字符串在 Lua 为真** → `result and "成功" or "失败"` 恒"成功" | 检查退出码（`os.execute` 返回值或改为捕获 rc），记录真实结果 |
| H2 | `mqtt_client.lua:487-518` | "已连接"判定 = **sub 进程存活**；mosquitto_sub 断线后进程内自动重连、进程不死 → 实际离线仍显示"已连接" | 用输出文件中的连接事件/心跳判定，或与 broker 双向确认；至少把状态名改为"订阅进程存活" |
| H3 | `mqtt_client.lua:332-340` | `broker/topic/client_id` 以 `'%s'` 拼入 `sh -c` 字符串，含单引号可破坏/注入（输入均需 LuCI 管理权限，故定"高"） | 用 `%q` 转义，或 `nixio.spawn`（argv 表，不经 shell） |
| H4 | `root/etc/init.d/xiaoai-mqtt:35-39` | `procd_set_param env` 三次调用（L36 与 L39 重复 LUA_CPATH）；L38 注释声称"停止超时 30 秒"但无 `procd_set_param timeout`；`start_service` 不清理残留 sub（配合 S6） | 合并为一次 env 调用；补 `timeout 30`（或 `term_timeout`）；start 前清理残留 sub |
| H5 | `controller/xiaoai-mqtt.lua:44` | "重新连接"向 **mosquitto_sub** 发 SIGHUP（`kill -1`），而 mosquitto_sub 对 SIGHUP 的默认行为是**退出**而非重连——实际是"杀掉等主循环重启"，提示文案误导且有竞态 | **按用户决定**：改为调用 `/etc/init.d/xiaoai-mqtt restart`，删除 SIGHUP 逻辑 |
| H6 | `Makefile:13` | 依赖三处问题：① **`+lua` 不含 nixio**——IW 24.10 上 nixio 由 `luci-lua-nixio` 提供，未声明则裸机 `require("nixio")` 失败、服务退出；② `+mosquitto-client` 包名未验证（24.10 包源确认存在的是 `mosquitto-client-ssl`/`mosquitto-client-nossl`）；③ `samba4-admin` 需核实 `net` 二进制路径（代码硬编码 `/usr/bin/net`，可能在 `/usr/sbin/net`） | `LUCI_DEPENDS` 改为 `+luci-base +luci-lua-nixio +mosquitto-client-nossl +etherwake +samba4-admin`（按"不需要 TLS"决策用 nossl；包名在 SDK 的 `make menuconfig` 实测确认；`net` 路径核实后修正代码） |
| H7 | `luasrc/view/xiaoai-mqtt/log.htm:31-35` | 清空日志用**普通 HTML form POST**；现代 LuCI 对 POST 校验 CSRF token（`L.Request.post` 会自动带 `X-CSRF-Token`，普通表单不会）→ **大概率 403**（需目标机验证） | 表单加隐藏 token 字段，或改用 JS `L.Request.post` |

### 2.3 🟡 中低（M1–M13）

| 编号 | 位置 | 问题 | 修复要点 |
|---|---|---|---|
| M1 | `basic.lua`、`log.lua`、`status.htm`、`status.sh` | 死代码 + 双 UI 分叉：控制器只挂载 JS view，CBI 模型从未引用；`basic.lua:78/80` 重定向到不存在的 `admin/services/xiaoai-mqtt/basic` → 404；两套 UI 字段标签/默认值已不一致（"客户端ID" vs "巴法云key"）；`status.sh` 安装但从未调用 | **按用户决定（我来定）**：保留 JS view（index.js），删除 4 个死文件，Makefile 同步删安装项 |
| M2 | `basic.lua:122`、`controller:177` | 直接使用全局 `nixio`（未 `require`）；LuCI Web 环境通常已提供该全局，500 概率低，但防御性应补 | `local nixio = require "nixio"` |
| M3 | `mqtt_client.lua:253-263` | `update_status` 非关键 key 每 10 次才写盘 → heartbeat 延迟约 30s；白名单中的 `reconnecting` 服务侧从不写入（只有控制器写） | heartbeat 独立降频写盘；`reconnecting` 由服务侧写或删除该状态 |
| M4 | `mqtt_client.lua:411` | `content:match("Connection refused.-\n")` 可能返回 nil → 字符串拼接报错 → 被 pcall 吞掉 → **`os.exit(1)` 不执行** → 循环刷"主循环严重错误" | `match(...) or "未知原因"` 兜底 |
| M5 | 默认配置（`config` 文件） | `mac/ip/user/pass` 均为空：触发词命中时用空参数执行 etherwake/net 并失败，叠加 H1 还记"成功" | 参数为空时跳过并写警告日志 |
| M6 | `Makefile:4` | `PKG_VERSION:=V1.0.0` 的 `V` 前缀不合 OpenWrt 惯例 | 改为 `1.0.0` |
| M7 | `config:1` vs `index.js:16` | `config global 'status'`（类型 global）与 `NamedSection('status','status')` 不一致；"保存会追加多余段"的后果未验证（uci 段名唯一，更可能原地编辑） | 统一为 `config status 'status'`；后果描述以实测为准 |
| M8 | `log.htm:11-15,57-66` | 每 5 秒整页 fetch，服务端每次重跑 `ls/wc/tail`；`luci.util.exec(...) or "0B"` 兜底无效（"" 为真） | 提供 JSON 接口只拉日志内容与统计；空结果显式判断 |
| M9 | `README-COMPILE.md:37`、`.github/workflows/*` | README 引用不存在的 `build.yml`；工作流 `actions/checkout@v2` 已被 GitHub 废弃（node12，直接失败）；多处 `${{ }}` 未加引号 | **按用户"仅本地编译"决定**：删除 `.github/workflows/`，README 只保留本地编译章节 |
| M10 | `mqtt_client.lua:516` | 3 秒 tick → WOL/关机延迟约 3–6 秒 | 可接受，README 注明 |
| M11 | `index.js:353-360、399-406` | 按钮失败路径**不恢复 disabled/文案**，按钮永远卡在"请求失败" | 失败时恢复按钮原状态 |
| M12 | `mqtt_client.lua:39-60` | `write_log` 每次 `io.open/close` 日志文件，高频消息下 IO 开销大 | 缓冲写入或降低写频率 |
| M13 | `controller:139-151` | `get_status` 每次轮询遍历日志文件统计行数（上限 1 万行） | 改用 `wc -l` |

### 2.4 🟢 清理（L1–L5）

| 编号 | 位置 | 问题 |
|---|---|---|
| L1 | `mqtt_client.lua:342` | `cmd:gsub(" -P '%S+'", "")` 是空操作；且日志会记录完整命令（含 client_id/topic） |
| L2 | `mqtt_client.lua:12-23,197-207` 等 | 大量"调试：..."日志残留生产代码，建议环境变量控制日志级别 |
| L3 | `controller:183-317` | `start/stop/restart_service` 三处状态文件更新逻辑重复，可抽公共函数 |
| L4 | `root/etc/config/xiaoai-mqtt:7` | tab/空格缩进混用（不影响功能） |
| L5 | `config:19` | SMB 密码明文存 UCI（日志已脱敏，但 UCI 本身明文，README 提示） |

---

## 3. 已确认的决策（用户答复）

| 问题 | 答复 | 对计划的影响 |
|---|---|---|
| 目标固件/平台 | ImmortalWrt 24.10 / x86_64 | 依赖按此版本核实（`luci-lua-nixio`、`mosquitto-client-nossl`） |
| MQTT 认证 | 私钥即 client_id，用户名/密码为空或随意，**不需要账号密码** | S7 修复方向 = **删除** `mqtt_user/mqtt_pass` 字段（不做 `-u/-P`） |
| "重新连接"语义 | 彻底重启订阅进程 | H5 修复 = `/etc/init.d/xiaoai-mqtt restart` |
| UI 实现 | 你来定 | **保留 JS view（index.js），删除 CBI 死代码**（M1） |
| 编译方式 | 仅本地编译 | **删除 `.github/workflows/`**（M9），README 只留本地编译 |
| WOL 网卡 | 做成可配置 | 新增"唤醒网卡"UCI 字段 + UI 项，默认 `br-lan` |
| MQTT TLS | 不需要 | 依赖用 `mosquitto-client-nossl`（H6） |
| 是否实施修复 | **暂不修改，仅保留计划** | 本报告即交付物；文件保持原样 |

---

## 4. 修复计划

### 阶段 1 — 严重（S1–S8，优先于一切）

1. **S1**：`mqtt_client.lua:333` 端口改 `tonumber(config.mqtt_port)` 并校验 1–65535，无效则 `write_log` 明确报错并 `return nil`（不再崩溃重试）。
2. **S2 + H3**：`execute_shutdown` 与 `start_mosquitto_sub` 所有外部输入（`ip/user/pass/broker/topic/client_id`）改 `%q` 转义；`-U` 传 `%q` 包裹的 `user%pass` 组合串。
3. **S3**：`index.js` 4 处 POST 回调统一——保留 `{json:true}`，回调参数直接当对象用（删除 `JSON.parse(xhr.responseText)`），加 `typeof` 兜底。
4. **S4**：控制器 4 处 `pgrep -f 'lua /etc/...'` 改 `pgrep -f '[l]ua /etc/...'`；`get_status` 优先 pidfile + `/proc/<pid>`，pgrep 仅作兜底。
5. **S5**：消息通道重写——sub 命令改 `>>` 追加写；Lua 端持久化读偏移（`file:seek("set", offset)` 读至 EOF，更新 offset）；文件超阈值（如 1MB）时截断并重置 offset（append 模式截断安全）；删除"取 8KB 清空整文件"与"超 50 条丢弃"，处理不完留到下一轮。
6. **S6**：`start_mosquitto_sub` 启动前先按 pidfile + `pgrep -f mosquitto_sub` 清理残留实例；"Connection refused" 分支不再 `os.exit(1)`（退避重启已覆盖）；"Not authorized" 退出前先杀 sub。
7. **S7**：删除 `mqtt_user/mqtt_pass`（config、UI、文档），README 注明"私钥即 client_id"。
8. **S8**：日志脱敏——`execute_shutdown` 的日志只记 `-U 'user%******'` 或直接不记凭据；全项目保证任何命令的明文密码不落日志。

### 阶段 2 — 高（H1–H7）

9. **H1**：WOL/关机改用能拿到退出码的执行方式（`os.execute` 返回码或 `nixio.spawn`），记录真实成败；参数为空时跳过并写警告（M5 一并处理）。
10. **H2**：连接状态语义修正——不再以"进程存活"冒充"已连接"（输出文件中检测连接事件 / 明确标注为"订阅进程状态"）。
11. **H4**：init.d 合并 env 为一次调用；补 `procd_set_param timeout 30`（或按注释意图）；`start_service` 增加残留 sub 清理。
12. **H5**：controller `reconnect_mqtt` 改为调用 `/etc/init.d/xiaoai-mqtt restart`，删除 SIGHUP 逻辑。
13. **H6**：Makefile `LUCI_DEPENDS` 改为 `+luci-base +luci-lua-nixio +mosquitto-client-nossl +etherwake +samba4-admin`；删除未定义的 `PKG_CONFIG_DEPENDS`（`INCLUDE_MQTT_SSL`）；在 SDK 中实测确认包名；核实 `net` 实际路径（`/usr/bin/net` 或 `/usr/sbin/net`）并修正代码。
14. **H7**：`log.htm` 清空日志改为 JS `L.Request.post` 或表单加 CSRF 隐藏 token；目标机验证 403 是否复现。
15. **WOL 可配置**（用户决策）：UCI 新增 `wol.wol_iface`（默认 `br-lan`），JS view 增加输入项，`execute_wol` 不再硬编码。

### 阶段 3 — 中低与清理（M/L）

16. **M1**：删除 `basic.lua`、`log.lua`、`status.htm`、`status.sh`；Makefile 同步删除对应安装行。
17. **M2**：`basic.lua`（若保留）/controller `download_log` 补 `local nixio = require "nixio"`。
18. **M3**：heartbeat 独立降频写盘；`reconnecting` 状态由服务侧维护或删除。
19. **M4**：`match(...) or "未知原因"` 兜底。
20. **M6**：`PKG_VERSION` 改 `1.0.0`。
21. **M7**：`config` 改为 `config status 'status'`（与 UI 对齐）。
22. **M8**：日志页改 JSON 接口（仅返回日志尾部 + 统计），空结果显式判断。
23. **M9**：删除 `.github/workflows/`；README 重写（依赖清单、目录结构、本地编译步骤、WOL 网卡说明、3–6 秒延迟说明）。
24. **M11**：按钮失败路径恢复原状态。
25. **M12/M13**：`write_log` 缓冲、`get_status` 用 `wc -l`。
26. **L1–L5**：删除空操作 gsub 与命令日志、日志级别化、抽取公共状态更新函数、config 缩进规范、README 注明 UCI 明文密码风险。

### 阶段 4 — 验证（实施后）

**静态检查**
- `luac -p` 全部 Lua 文件（`mqtt_client.lua`、controller、CBI——若保留）。
- JS 文件静态检查（`node --check index.js` 或浏览器控制台）。

**目标机功能验证（ImmortalWrt 24.10 x86_64）**
1. **S1/S4**：`/etc/init.d/xiaoai-mqtt stop` 后 Web 状态页应显示"已停止"；点"启动服务"应真正拉起进程并显示"运行中"。
2. **S3**：4 个按钮（重连/启动/停止/重启）点击后反馈与实际操作一致，无"请求失败"误报。
3. **S7/S8**：`mosquitto_pub -h bemfa.com -p 9501 -t <topic> -i <私钥> -m on` 能触发 WOL；`-m off` 能触发关机；`grep -a 'pass|user' /var/log/xiaoai-mqtt.log` 无明文密码。
4. **S5**：长时间运行后 `od -c /tmp/mosquitto_sub.out` 确认无 NUL 空洞、消息持续可处理。
5. **S6**：`kill -9` Lua 主进程反复多次，确认无孤儿 mosquitto_sub、无同 client_id 会话抢占（`ps | grep mosquitto` 恒为 1 个）。
6. **H7**：点击"清空日志"确认非 403。

---

## 5. 实施时预计修改的文件

| 文件 | 变更 |
|---|---|
| `root/etc/xiaoai-mqtt/mqtt_client.lua` | S1/S2/S5/S6/S7/S8/H1/H2/M3/M4/M12/L1/L2 |
| `htdocs/luci-static/resources/view/xiaoai-mqtt/index.js` | S3/M11/M7（WOL 网卡字段） |
| `root/usr/lib/lua/luci/controller/xiaoai-mqtt.lua` | S4/H5/M2/M13/L3 |
| `root/etc/init.d/xiaoai-mqtt` | H4 |
| `Makefile` | H6/M6/M1（删安装项） |
| `root/etc/config/xiaoai-mqtt` | S7/M7/L4/L5（新增 `wol_iface`） |
| `luasrc/view/xiaoai-mqtt/log.htm` | H7/M8 |
| `README-COMPILE.md` | M9/M10/L5 |
| `.github/workflows/build-immortalwrt.yml` | 删除 |
| `root/usr/lib/lua/luci/model/cbi/xiaoai-mqtt/basic.lua` | 删除 |
| `root/usr/lib/lua/luci/model/cbi/xiaoai-mqtt/log.lua` | 删除 |
| `luasrc/view/xiaoai-mqtt/status.htm` | 删除 |
| `root/etc/xiaoai-mqtt/status.sh` | 删除 |

---

## 6. 实施状态（修订）

> 已按用户指示开始实施（2025）。实施过程中相对计划的两处技术性调整：
> 1. **S2/H3 转义**：计划写 `%q`，实施中发现 Lua 的 `%q` 对 shell 并非完全安全（`$`、反引号不转义），改用自实现 `shell_quote`（单引号包裹 + `'\''` 转义）。
> 2. **S6 错误处理**：计划"Connection refused 不再 os.exit"，实施中改为 process_messages 返回 `"fatal"`，主循环杀 sub 并**指数退避**（5→300 秒）后重启，避免 5 秒密集重启。
> 3. **M12**：`write_log` 缓冲写入会牺牲日志持久性（进程被杀丢日志），保留每次 open/close 的现状，未做缓冲。
