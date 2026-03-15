--- @revenant-script
--- name: pkg_worker
--- version: 0.1.0
--- author: Sordal
--- description: Background worker for pkg GUI operations

local args_lib = require("lib/args")
local _parsed = args_lib.parse(Script.vars[0] or "")
local cmd = _parsed.args[1]
local positional = {}
for i = 2, #_parsed.args do positional[i-1] = _parsed.args[i] end

if cmd == "install" then
    local install = require("cmd_install")
    install.run(positional, { force = _parsed.force })
elseif cmd == "update" then
    local update = require("cmd_update")
    update.run(positional, _parsed)
elseif cmd == "map-update" then
    local map = require("cmd_map")
    map.run_update()
else
    respond("pkg_worker: unknown command: " .. tostring(cmd))
end
