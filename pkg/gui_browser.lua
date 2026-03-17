local config = require("config")
local registry = require("registry")
local cmd_map = require("cmd_map")

local M = {}

local selected_script = nil
local worker_running = false
local current_filter = "All"
local current_sort = "Name"
local filter_modes = { "All", "Installed", "Available", "Updates" }
local sort_modes = { "Name", "Updated", "Author" }

local function time_ago(epoch)
    if not epoch then return "-" end
    local diff = os.time() - epoch
    if diff < 3600 then return math.floor(diff / 60) .. "m ago"
    elseif diff < 86400 then return math.floor(diff / 3600) .. "h ago"
    elseif diff < 604800 then return math.floor(diff / 86400) .. "d ago"
    else return os.date("%Y-%m-%d", epoch)
    end
end

local function get_version(entry)
    if entry.channels and entry.channels.stable then
        return entry.channels.stable.version or "-"
    end
    return "-"
end

local function cycle_value(current, options)
    for i, v in ipairs(options) do
        if v == current then
            return options[(i % #options) + 1]
        end
    end
    return options[1]
end

local function load_script_data()
    local cfg = config.load_config()
    local installed = config.load_installed()
    local manifests = registry.fetch_all_manifests(cfg, true, { scripts_only = true })

    local scripts = {}
    for _, entry in ipairs(manifests) do
        for _, script in ipairs(entry.manifest.scripts or {}) do
            scripts[#scripts + 1] = {
                name = script.name,
                description = script.description or "",
                tags = script.tags or {},
                author = script.author or "-",
                channels = script.channels,
                last_updated = script.last_updated,
                registry_name = entry.registry.name,
                installed = installed[script.name] ~= nil,
                installed_version = installed[script.name] and installed[script.name].version,
            }
        end
    end
    return scripts, installed
end

local function filter_and_sort(scripts, search_text, filter_mode, sort_mode)
    local filtered = {}
    for _, s in ipairs(scripts) do
        local pass = true

        if filter_mode == "Installed" and not s.installed then pass = false end
        if filter_mode == "Available" and s.installed then pass = false end
        if filter_mode == "Updates" then
            if not s.installed then
                pass = false
            else
                local remote_ver = get_version(s)
                if remote_ver == "-" or remote_ver == s.installed_version then
                    pass = false
                end
            end
        end

        if pass and search_text and search_text ~= "" then
            local haystack = (s.name .. " " .. s.description .. " " .. table.concat(s.tags, " ")):lower()
            if not haystack:find(search_text:lower(), 1, true) then
                pass = false
            end
        end

        if pass then filtered[#filtered + 1] = s end
    end

    if sort_mode == "Name" then
        table.sort(filtered, function(a, b) return a.name < b.name end)
    elseif sort_mode == "Updated" then
        table.sort(filtered, function(a, b) return (a.last_updated or 0) > (b.last_updated or 0) end)
    elseif sort_mode == "Author" then
        table.sort(filtered, function(a, b) return (a.author or "") < (b.author or "") end)
    end

    return filtered
end

local function rebuild_table_rows(script_table, scripts)
    script_table:clear()
    for _, s in ipairs(scripts) do
        local marker = s.installed and "* " or "  "
        local tags_str = table.concat(s.tags or {}, ",")
        if #tags_str > 12 then tags_str = tags_str:sub(1, 11) .. "+" end
        script_table:add_row({ marker .. s.name, get_version(s), tags_str })
    end
end

function M.run(positional, flags)
    local win = Gui.window("Revenant Package Manager", { width = 900, height = 600 })
    local root = Gui.vbox()

    -- Toolbar
    local toolbar = Gui.hbox()
    local search_input = Gui.input({ placeholder = "Search by name..." })
    toolbar:add(search_input)
    local filter_btn = Gui.button("Filter: All")
    toolbar:add(filter_btn)
    local sort_btn = Gui.button("Sort: Name")
    toolbar:add(sort_btn)
    root:add(toolbar)

    -- Main content: table + detail
    local content = Gui.hbox()

    local script_table = Gui.table({ columns = { "Name", "Version", "Tags" } })
    content:add(script_table)

    -- Detail panel
    local detail_box = Gui.vbox()
    local detail_name = Gui.label("Select a script")
    detail_box:add(detail_name)
    local detail_author = Gui.label("")
    detail_box:add(detail_author)
    local detail_tags = Gui.label("")
    detail_box:add(detail_tags)
    local detail_updated = Gui.label("")
    detail_box:add(detail_updated)
    local detail_registry = Gui.label("")
    detail_box:add(detail_registry)
    local detail_desc = Gui.label("")
    detail_box:add(detail_desc)
    detail_box:add(Gui.separator())
    local action_btn = Gui.button("Install")
    detail_box:add(action_btn)
    content:add(detail_box)
    root:add(content)

    -- Status bar
    local status_bar = Gui.hbox()
    local status_label = Gui.label("Loading...")
    status_bar:add(status_label)
    local update_all_btn = Gui.button("Update All")
    status_bar:add(update_all_btn)
    root:add(status_bar)

    -- Map section
    root:add(Gui.separator())
    local map_header = Gui.label("Map Database")
    root:add(map_header)
    local map_status = Gui.label("")
    root:add(map_status)
    local map_images = Gui.label("")
    root:add(map_images)
    local map_btn = Gui.button("Update Map Database")
    root:add(map_btn)
    local map_progress = Gui.progress(0)
    root:add(map_progress)

    -- Settings section
    root:add(Gui.separator())
    root:add(Gui.label("Settings"))
    root:add(Gui.label("Registries:"))
    local registries_table = Gui.table({ columns = { "Name", "Format", "Map", "URL" } })
    root:add(registries_table)
    local settings_bar = Gui.hbox()
    local reg_name_input = Gui.input({ placeholder = "Registry name" })
    settings_bar:add(reg_name_input)
    local reg_url_input = Gui.input({ placeholder = "Registry URL" })
    settings_bar:add(reg_url_input)
    local reg_add_btn = Gui.button("Add Registry")
    settings_bar:add(reg_add_btn)
    root:add(settings_bar)
    local channel_label = Gui.label("")
    root:add(channel_label)
    local channel_btn = Gui.button("Change Channel")
    root:add(channel_btn)

    win:set_root(Gui.scroll(root))

    -- Load data
    local cfg = config.load_config()
    local all_scripts, installed = load_script_data()
    local filtered = filter_and_sort(all_scripts, "", current_filter, current_sort)
    rebuild_table_rows(script_table, filtered)
    status_label:set_text(#all_scripts .. " scripts across registries")

    -- Populate map info
    local game = nil
    local ok, gs = pcall(function() return GameState and GameState.game end)
    if ok and gs and gs ~= "" then game = gs end
    if game then
        local map_regs = registry.get_registries(cfg, { map_only = true })
        if #map_regs > 0 then
            map_status:set_text("Game: " .. game .. " | Registry: " .. map_regs[1].name)
            map_images:set_text("Run Update to check for new map data")
        else
            map_status:set_text("No map registries configured")
        end
    else
        map_status:set_text("Log in to a game to see map status")
    end

    -- Populate settings
    local function refresh_registries_table()
        local current_cfg = config.load_config()
        registries_table:clear()
        for _, reg in ipairs(current_cfg.registries) do
            registries_table:add_row({
                reg.name,
                reg.format or "revenant",
                reg.map_registry and "yes" or "",
                reg.url,
            })
        end
        local ch = current_cfg.channel or "stable"
        channel_label:set_text("Global channel: " .. ch)
    end
    refresh_registries_table()

    -- Callbacks
    search_input:on_change(function(text)
        filtered = filter_and_sort(all_scripts, text, current_filter, current_sort)
        rebuild_table_rows(script_table, filtered)
    end)

    filter_btn:on_click(function()
        current_filter = cycle_value(current_filter, filter_modes)
        filter_btn:set_text("Filter: " .. current_filter)
        filtered = filter_and_sort(all_scripts,
            search_input:get_text(), current_filter, current_sort)
        rebuild_table_rows(script_table, filtered)
    end)

    sort_btn:on_click(function()
        current_sort = cycle_value(current_sort, sort_modes)
        sort_btn:set_text("Sort: " .. current_sort)
        filtered = filter_and_sort(all_scripts,
            search_input:get_text(), current_filter, current_sort)
        rebuild_table_rows(script_table, filtered)
    end)

    script_table:on_click(function(row_idx)
        if row_idx and filtered[row_idx] then
            selected_script = filtered[row_idx]
            local s = selected_script
            detail_name:set_text(s.name .. " v" .. get_version(s))
            detail_author:set_text("by: " .. s.author)
            detail_tags:set_text("tags: " .. table.concat(s.tags, ", "))
            detail_updated:set_text("updated: " .. time_ago(s.last_updated))
            detail_registry:set_text("registry: " .. s.registry_name)
            detail_desc:set_text(s.description)

            if not s.installed then
                action_btn:set_text("Install")
            else
                local remote_ver = get_version(s)
                if remote_ver ~= "-" and remote_ver ~= s.installed_version then
                    action_btn:set_text("Update")
                else
                    action_btn:set_text("Installed")
                end
            end
        end
    end)

    action_btn:on_click(function()
        if not selected_script or worker_running then return end
        local s = selected_script
        if not s.installed then
            worker_running = true
            action_btn:set_text("Working...")
            status_label:set_text("Installing " .. s.name .. "...")
            Script.run("pkg_worker", { "install", s.name })
        else
            local remote_ver = get_version(s)
            if remote_ver ~= "-" and remote_ver ~= s.installed_version then
                worker_running = true
                action_btn:set_text("Working...")
                status_label:set_text("Updating " .. s.name .. "...")
                Script.run("pkg_worker", { "update", s.name })
            end
        end
    end)

    update_all_btn:on_click(function()
        if worker_running then return end
        worker_running = true
        status_label:set_text("Updating all scripts...")
        Script.run("pkg_worker", { "update" })
    end)

    map_btn:on_click(function()
        if worker_running then return end
        worker_running = true
        map_btn:set_text("Updating...")
        status_label:set_text("Updating map database...")
        Script.run("pkg_worker", { "map-update" })
    end)

    reg_add_btn:on_click(function()
        local rname = reg_name_input:get_text()
        local rurl = reg_url_input:get_text()
        if rname and rname ~= "" and rurl and rurl ~= "" then
            local cmd_repo = require("cmd_repo")
            cmd_repo.run({ "add", rname, rurl }, flags or {})
            refresh_registries_table()
        end
    end)

    channel_btn:on_click(function()
        local current_cfg = config.load_config()
        local ch = current_cfg.channel or "stable"
        local channels = { "stable", "beta", "dev" }
        for i, v in ipairs(channels) do
            if v == ch then
                current_cfg.channel = channels[(i % #channels) + 1]
                break
            end
        end
        config.save_config(current_cfg)
        refresh_registries_table()
    end)

    win:show()
    Gui.wait(win, "close")
end

return M
