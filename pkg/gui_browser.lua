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

local function build_table_rows(scripts)
    local rows = {}
    for _, s in ipairs(scripts) do
        local marker = s.installed and "* " or "  "
        local tags_str = table.concat(s.tags or {}, ",")
        if #tags_str > 12 then tags_str = tags_str:sub(1, 11) .. "+" end
        rows[#rows + 1] = { marker .. s.name, get_version(s), tags_str }
    end
    return rows
end

function M.run(positional, flags)
    local win = Gui.window("Revenant Package Manager", 900, 600)

    -- Scripts tab
    local scripts_tab = Gui.vbox(win)

    -- Toolbar
    local toolbar = Gui.hbox(scripts_tab)
    local search_input = Gui.input(toolbar, { placeholder = "Search by name..." })
    local filter_btn = Gui.button(toolbar, "Filter: All")
    local sort_btn = Gui.button(toolbar, "Sort: Name")

    -- Main content: table + detail
    local content = Gui.hbox(scripts_tab)

    local script_table = Gui.table(content, {
        columns = { "Name", "Version", "Tags" },
        rows = {},
    })

    -- Detail panel
    local detail_box = Gui.vbox(content)
    local detail_name = Gui.label(detail_box, "Select a script")
    local detail_author = Gui.label(detail_box, "")
    local detail_tags = Gui.label(detail_box, "")
    local detail_updated = Gui.label(detail_box, "")
    local detail_registry = Gui.label(detail_box, "")
    local detail_desc = Gui.label(detail_box, "")
    Gui.separator(detail_box)
    local action_btn = Gui.button(detail_box, "Install")

    -- Status bar
    local status_bar = Gui.hbox(scripts_tab)
    local status_label = Gui.label(status_bar, "Loading...")
    local update_all_btn = Gui.button(status_bar, "Update All")

    -- Map section
    Gui.separator(scripts_tab)
    local map_header = Gui.label(scripts_tab, "Map Database")
    local map_status = Gui.label(scripts_tab, "")
    local map_images = Gui.label(scripts_tab, "")
    local map_btn = Gui.button(scripts_tab, "Update Map Database")
    local map_progress = Gui.progress(scripts_tab, 0)

    -- Load data
    local cfg = config.load_config()
    local all_scripts, installed = load_script_data()
    local filtered = filter_and_sort(all_scripts, "", current_filter, current_sort)
    Gui.update(script_table, { rows = build_table_rows(filtered) })
    Gui.update(status_label, { text = #all_scripts .. " scripts across registries" })

    -- Populate map info
    local game = nil
    local ok, gs = pcall(function() return GameState and GameState.game end)
    if ok and gs and gs ~= "" then game = gs end
    if game then
        local map_regs = registry.get_registries(cfg, { map_only = true })
        if #map_regs > 0 then
            Gui.update(map_status, { text = "Game: " .. game .. " | Registry: " .. map_regs[1].name })
            -- Count local images would require fetching manifest, skip for initial load
            Gui.update(map_images, { text = "Run Update to check for new map data" })
        else
            Gui.update(map_status, { text = "No map registries configured" })
        end
    else
        Gui.update(map_status, { text = "Log in to a game to see map status" })
    end

    win:show()

    -- Event loop
    while win:alive() do
        local event = win:wait()
        if not event then
            -- Check if worker finished
            if worker_running and not Script.running("pkg_worker") then
                worker_running = false
                Gui.update(status_label, { text = "Operation complete." })
                Gui.update(action_btn, { label = "Install" })
                all_scripts, installed = load_script_data()
                filtered = filter_and_sort(all_scripts, "", current_filter, current_sort)
                Gui.update(script_table, { rows = build_table_rows(filtered) })
            end
        elseif event.type == "clicked" then
            if event.widget == filter_btn then
                current_filter = cycle_value(current_filter, filter_modes)
                Gui.update(filter_btn, { label = "Filter: " .. current_filter })
                filtered = filter_and_sort(all_scripts,
                    Gui.get_text(search_input), current_filter, current_sort)
                Gui.update(script_table, { rows = build_table_rows(filtered) })
            elseif event.widget == sort_btn then
                current_sort = cycle_value(current_sort, sort_modes)
                Gui.update(sort_btn, { label = "Sort: " .. current_sort })
                filtered = filter_and_sort(all_scripts,
                    Gui.get_text(search_input), current_filter, current_sort)
                Gui.update(script_table, { rows = build_table_rows(filtered) })
            elseif event.widget == action_btn and selected_script and not worker_running then
                local s = selected_script
                if not s.installed then
                    worker_running = true
                    Gui.update(action_btn, { label = "Working..." })
                    Gui.update(status_label, { text = "Installing " .. s.name .. "..." })
                    Script.run("pkg_worker", { "install", s.name })
                else
                    local remote_ver = get_version(s)
                    if remote_ver ~= "-" and remote_ver ~= s.installed_version then
                        worker_running = true
                        Gui.update(action_btn, { label = "Working..." })
                        Gui.update(status_label, { text = "Updating " .. s.name .. "..." })
                        Script.run("pkg_worker", { "update", s.name })
                    end
                end
            elseif event.widget == update_all_btn and not worker_running then
                worker_running = true
                Gui.update(status_label, { text = "Updating all scripts..." })
                Script.run("pkg_worker", { "update" })
            elseif event.widget == map_btn and not worker_running then
                worker_running = true
                Gui.update(map_btn, { label = "Updating..." })
                Gui.update(status_label, { text = "Updating map database..." })
                Script.run("pkg_worker", { "map-update" })
            end
        elseif event.type == "table_row_selected" then
            if event.widget == script_table then
                local idx = event.row
                if idx and filtered[idx] then
                    selected_script = filtered[idx]
                    local s = selected_script
                    Gui.update(detail_name, { text = s.name .. " v" .. get_version(s) })
                    Gui.update(detail_author, { text = "by: " .. s.author })
                    Gui.update(detail_tags, { text = "tags: " .. table.concat(s.tags, ", ") })
                    Gui.update(detail_updated, { text = "updated: " .. time_ago(s.last_updated) })
                    Gui.update(detail_registry, { text = "registry: " .. s.registry_name })
                    Gui.update(detail_desc, { text = s.description })

                    if not s.installed then
                        Gui.update(action_btn, { label = "Install" })
                    else
                        local remote_ver = get_version(s)
                        if remote_ver ~= "-" and remote_ver ~= s.installed_version then
                            Gui.update(action_btn, { label = "Update" })
                        else
                            Gui.update(action_btn, { label = "Installed" })
                        end
                    end
                end
            end
        elseif event.type == "changed" then
            if event.widget == search_input then
                filtered = filter_and_sort(all_scripts,
                    event.text, current_filter, current_sort)
                Gui.update(script_table, { rows = build_table_rows(filtered) })
            end
        end
    end
end

return M
