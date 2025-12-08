local uci = luci.model.uci.cursor()
local sys = require "luci.sys"

m = Map("xiaoai-mqtt", translate("日志管理"),
    translate("集成日志查看与管理功能"))

s = m:section(TypedSection, "log", translate("日志操作"))
s.anonymous = true

-- 单模板集成所有功能
s:option(DummyValue, "_all", "").template = "xiaoai-mqtt/log"

return m