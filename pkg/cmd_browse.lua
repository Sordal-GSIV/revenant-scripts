local config = require("config")
local registry = require("registry")

local M = {}

local PAGE_SIZE = 25

local function matches_search(entry, terms)
    if not terms or #terms == 0 then return true end
    local haystack = ((entry.name or "") .. " " .. (entry.description or "") .. " "
        .. table.concat(entry.tags or {}, " ")):lower()
    for _, term in ipairs(terms) do
        if haystack:find(term:lower(), 1, true) then
            return true
        end
    end
    return false
end

local function matches_tag(entry, tag)
    if not tag then return true end
    tag = tag:lower()
    for _, t in ipairs(entry.tags or {}) do
        if t:lower() == tag then return true end
    end
    return false
end

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

function M.run(positional, flags)
    local cfg = config.load_config()
    local installed = config.load_installed()

    -- Fetch manifests from script registries only
    local manifests = registry.fetch_all_manifests(cfg, true, { scripts_only = true })
    if #manifests == 0 then
        respond("No script registries available.")
        return
    end

    -- Merge all scripts into a single list
    local all_scripts = {}
    for _, entry in ipairs(manifests) do
        for _, script in ipairs(entry.manifest.scripts or {}) do
            all_scripts[#all_scripts + 1] = {
                name = script.name,
                description = script.description or "",
                tags = script.tags or {},
                author = script.author or "-",
                channels = script.channels,
                last_updated = script.last_updated,
                registry = entry.registry.name,
                installed = installed[script.name] ~= nil,
            }
        end
    end

    -- Apply filters
    local filtered = {}
    local tag_filter = flags.tag
    local show_installed = flags.installed
    local show_available = flags.available

    for _, s in ipairs(all_scripts) do
        local pass = true
        if show_installed and not s.installed then pass = false end
        if show_available and s.installed then pass = false end
        if not matches_tag(s, tag_filter) then pass = false end
        if not matches_search(s, positional) then pass = false end
        if pass then filtered[#filtered + 1] = s end
    end

    -- Sort
    local sort_key = flags.sort or "name"
    if sort_key == "name" then
        table.sort(filtered, function(a, b) return a.name < b.name end)
    elseif sort_key == "updated" then
        table.sort(filtered, function(a, b)
            return (a.last_updated or 0) > (b.last_updated or 0)
        end)
    elseif sort_key == "author" then
        table.sort(filtered, function(a, b) return (a.author or "") < (b.author or "") end)
    end

    -- Paginate
    local page = tonumber(flags.page) or 1
    local start_idx = (page - 1) * PAGE_SIZE + 1
    local end_idx = math.min(start_idx + PAGE_SIZE - 1, #filtered)

    -- Count registries
    local reg_set = {}
    for _, m in ipairs(manifests) do reg_set[m.registry.name] = true end
    local reg_count = 0
    for _ in pairs(reg_set) do reg_count = reg_count + 1 end

    -- Output
    respond("Available scripts (" .. reg_count .. " registries, " .. #filtered .. " scripts)")
    respond("")
    respond(string.format("  %-20s %-8s %-18s %s", "Name", "Version", "Tags", "Description"))
    respond("  " .. string.rep("-", 70))

    if start_idx > #filtered then
        respond("  (no results on this page)")
    else
        for i = start_idx, end_idx do
            local s = filtered[i]
            local marker = s.installed and "* " or "  "
            local tags_str = table.concat(s.tags or {}, ",")
            if #tags_str > 16 then tags_str = tags_str:sub(1, 15) .. "+" end
            local desc = s.description or ""
            if #desc > 30 then desc = desc:sub(1, 29) .. "+" end
            respond(string.format("%s%-20s %-8s %-18s %s",
                marker,
                s.name:sub(1, 20),
                get_version(s):sub(1, 8),
                tags_str,
                desc))
        end
    end

    respond("")
    local marker_note = "* = installed"
    if #filtered > end_idx then
        respond(marker_note .. "       Showing " .. start_idx .. "-" .. end_idx
            .. " of " .. #filtered .. ". Use --page=" .. (page + 1) .. " for more.")
    else
        respond(marker_note .. "       Showing " .. start_idx .. "-" .. end_idx .. " of " .. #filtered)
    end
end

return M
