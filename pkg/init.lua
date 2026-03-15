--- @revenant-script
--- name: pkg
--- version: 0.1.0
--- author: Sordal
--- description: Revenant package manager

local config = require("config")
local args_lib = require("lib/args")

local function show_help()
    respond("Usage: ;pkg <command> [args] [--flags]")
    respond("")
    respond("Commands:")
    respond("  install <name>     Install a script [--channel=<ch>] [--repo=<name>] [--force]")
    respond("  update [<name>]    Update one or all installed scripts")
    respond("  remove <name>      Remove an installed script")
    respond("  list               List installed scripts")
    respond("  search <query>     Search across registries")
    respond("  info <name>        Show script details")
    respond("  repo list          List configured registries")
    respond("  repo add <n> <u>   Add a registry")
    respond("  repo remove <n>    Remove a registry")
    respond("  channel [<ch>]     Get/set global channel (stable|beta|dev)")
    respond("  channel <n> <ch>   Set per-script channel override")
    respond("  check              Check for available updates")
    respond("  browse [terms]     Browse available scripts [--tag=x] [--sort=x] [--page=n]")
    respond("  map-update         Update map database from mapdb registry")
    respond("  map-info           Show map database status")
    respond("  gui                Open graphical package manager")
    respond("  help               Show this help")
end

local _parsed = args_lib.parse(Script.vars[0] or "")
local cmd = _parsed.args[1]
local positional = {}
for i = 2, #_parsed.args do positional[i-1] = _parsed.args[i] end
local flags = _parsed

if not cmd or cmd == "help" then
    show_help()
elseif cmd == "install" then
    local install = require("cmd_install")
    install.run(positional, flags)
elseif cmd == "update" then
    local update = require("cmd_update")
    update.run(positional, flags)
elseif cmd == "remove" then
    local remove = require("cmd_remove")
    remove.run(positional, flags)
elseif cmd == "list" then
    local list = require("cmd_list")
    list.run(positional, flags)
elseif cmd == "search" then
    local search = require("cmd_search")
    search.run(positional, flags)
elseif cmd == "info" then
    local info = require("cmd_info")
    info.run(positional, flags)
elseif cmd == "repo" then
    local repo = require("cmd_repo")
    repo.run(positional, flags)
elseif cmd == "channel" then
    local channel = require("cmd_channel")
    channel.run(positional, flags)
elseif cmd == "check" then
    local check = require("cmd_check")
    check.run(positional, flags)
elseif cmd == "browse" then
    local browse = require("cmd_browse")
    browse.run(positional, flags)
elseif cmd == "map-update" then
    local map = require("cmd_map")
    map.run({ "update" }, flags)
elseif cmd == "map-info" then
    local map = require("cmd_map")
    map.run({ "info" }, flags)
elseif cmd == "gui" then
    local gui = require("gui_browser")
    gui.run(positional, flags)
else
    respond("Unknown command: " .. cmd)
    respond("Run ;pkg help for usage")
end
