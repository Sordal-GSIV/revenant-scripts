--- @lic-certified: complete 2026-03-18
---
---   attempts to find the shortest route between any two rooms in the game
---   requires a map database
---
---   ;go2 help
---
---            author: Tillmen (tillmen@lichproject.org)
---   original author: Shaelun
---      contributors: Deysh, Doug, Gildaren, Sarvatt, Tysong, Xanlin, Dissonance,
---                    Rinualdo, Mahtra, Xanlin
---              port: Sordal (Revenant Lua conversion)
---              game: any
---              tags: core, movement
---           version: 2.2.13
---          required: Revenant ≥ 1.0.0
---
---   changelog:
---      2.2.13 (2026-03-18)
---        Revenant Lua conversion — full port of all go2.lic features
---        Added stringproc transpiler integration for wayto StringProc entries
---      2.2.13 (2025-11-22) [original]
---        Added support for ;go2 locker (CHE locker support)
---        Added support for ;go2 guild / guild shop
---
--- @revenant-script
--- name: go2
--- version: 2.2.13
--- author: Tillmen, Sordal
--- description: Room-to-room navigation with pathfinding, shortcuts, and transports

local settings    = require("settings")
local pathfinder  = require("pathfinder")
local movement    = require("movement")
local resolver    = require("resolver")

local ok_sp, stringproc = pcall(require, "lib/stringproc")
if ok_sp then
    local game = GameState.game or "GS3"
    stringproc.load_translations(game)
end

-------------------------------------------------------------------------------
-- Argument parsing
-- Format: ;go2 [options] [target]
-- Options: --key=value  or  --flag  or  --flag=on/off/yes/no/true/false
-------------------------------------------------------------------------------

local BOOL_MAP = {
    ["on"] = true, ["true"] = true, ["yes"] = true,
    ["off"] = false, ["false"] = false, ["no"] = false,
}

local function parse_bool(s)
    if s == nil then return true end  -- bare --flag means on
    return BOOL_MAP[s:lower()]
end

local raw_vars = Script.vars[0] or ""
local args_raw = {}
local options  = {}

for tok in raw_vars:gmatch("%S+") do
    local key, val = tok:match("^%-%-([%w_%-]+)=(.*)$")
    if key then
        options[key] = val
    elseif tok:match("^%-%-([%w_%-]+)$") then
        options[tok:match("^%-%-([%w_%-]+)$")] = true
    else
        args_raw[#args_raw + 1] = tok
    end
end

local function opt_bool(key, default)
    local v = options[key]
    if v == nil then return default end
    if v == true then return true end
    return parse_bool(tostring(v))
end

local function opt_num(key, default)
    local v = options[key]
    if v == nil then return default end
    return tonumber(v) or default
end

local function opt_str(key, default)
    local v = options[key]
    if v == nil then return default end
    return tostring(v)
end

local game = GameState.game or ""
local function is_gs()       return game:find("^GS") ~= nil end
local function is_dr()       return game:find("^DR") ~= nil end
local function is_plat()     return game == "GSPlat" end
local function is_shattered() return game == "GSF" end

local function as_time(secs)
    local m = math.floor(secs / 60)
    local s = secs % 60
    return string.format("%d:%04.1f", m, s)
end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local state = settings.load()
local uv    = settings.load_uservars()

-------------------------------------------------------------------------------
-- Command: help
-------------------------------------------------------------------------------

local function show_help()
    local sc = Script.name or "go2"
    respond("   Go2 v2.2.13")
    respond("")
    respond("   ;" .. sc .. " <target>               Navigate to target.")
    respond("   ;" .. sc .. " goback                 Return to last start room.")
    respond("   ;" .. sc .. " <options> <target>     Navigate with per-run options.")
    respond("   ;" .. sc .. " <options>              Save options without navigating.")
    respond("   ;" .. sc .. " setup                  Open settings GUI.")
    respond("")
    respond("   target:")
    respond("      Room number, UID (u12345), custom target name,")
    respond("      built-in tag (bank, inn, forge, ...), or room title text.")
    respond("")
    respond("   options:")
    respond("     --typeahead=<#>                Number of typeahead moves to send")
    respond("     --delay=<#>                   Seconds of delay between moves")
    respond("     --disable-confirm             Skip confirmation prompt for long paths")
    respond("     --hide-room-descriptions=<on|off>")
    respond("     --hide-room-titles=<on|off>")
    respond("     --echo-input=<on|off>")
    if is_gs() then
        respond("     --get-silvers=<on|off>        Allow bank withdrawal for travel costs")
        respond("     --get-return-trip-silvers=<on|off>")
        respond("     --ice-mode=<auto|wait|run>    Ice-room behavior")
        respond("     --stop-for-dead=<on|off>      Pause when dead body is seen")
        respond("     --shortcut=<on|off>           Use Ta'Vaalor shortcut")
        respond("     --use-seeking=<on|off>        Use Voln symbol of seeking")
        respond("     --use-urchins=<on|off>        Use urchin guides")
        respond("     --use-portmasters=<on|off>    Use portmasters")
        respond("     --use-day-pass=<on|off>       Use Chronomage day passes")
        respond("     --buy-day-pass=<on|off|locs>  Buy day passes if needed")
        respond("     --day-pass-container=<name>   Container for day passes")
        respond("     --instability=<room_id>       Force a specific instability room")
        respond("     --fwi-trinket=<name|off>      FWI trinket to use")
        respond("     --caravan-to-sos=<on|off>     Use caravan to Sanctum of Scales")
        respond("     --caravan-from-sos=<on|off>   Use caravan back from SoS")
        respond("     --use-gigas-hwtravel=<on|off> Use gigas fragments for Hinterwilds")
        respond("     --gigas-min-number=<#>        Min fragments before using (4-20)")
    end
    if is_plat() or is_shattered() then
        respond("     --portals=<on|off>            Use portals")
    end
    if is_plat() then
        respond("     --old-portals=<on|off>        Use old portals")
        respond("     --portal-pass=<on|off>        Have wearable portal pass")
    end
    if is_dr() then
        respond("     --drag=<name>                 Auto-drag character while moving")
    end
    respond("")
    respond("   other commands:")
    respond("      ;" .. sc .. " save <name>=<room_id|current>   Save custom target")
    respond("      ;" .. sc .. " save <name>=[1234,5678]         Save multi-room target")
    respond("      ;" .. sc .. " delete <name>                   Delete custom target")
    respond("      ;" .. sc .. " list                            Show settings & targets")
    respond("      ;" .. sc .. " targets                         Show built-in targets")
    respond("      ;" .. sc .. " reload                          Reload map database")
end

-------------------------------------------------------------------------------
-- Command: list
-------------------------------------------------------------------------------

local function show_list()
    respond("Go2 v2.2.13 settings:")
    respond("")
    respond("              typeahead: " .. (state.typeahead or 0))
    respond("                  delay: " .. (state.delay or 0))
    respond("             echo input: " .. (state.echo_input and "on" or "off"))
    respond("  hide room descriptions: " .. (state.hide_room_descriptions and "on" or "off"))
    respond("        hide room titles: " .. (state.hide_room_titles and "on" or "off"))
    if is_gs() then
        respond("             get silvers: " .. (state.get_silvers and "on" or "off"))
        respond("      get return silvers: " .. (state.get_return_silvers and "on" or "off"))
        respond("                ice mode: " .. (uv.mapdb_ice_mode or "auto"))
        respond("             use seeking: " .. (state.use_seeking and "on" or "off"))
        respond("             use urchins: " .. (uv.mapdb_use_urchins and "on" or "off"))
        respond("         use portmasters: " .. (uv.mapdb_use_portmasters and "on" or "off"))
        respond("            use day pass: " .. (uv.mapdb_use_day_pass and "on" or "off"))
        respond("            buy day pass: " .. (tostring(uv.mapdb_buy_day_pass or "off")))
        respond("      day pass container: " .. (uv.mapdb_day_pass_sack ~= "" and uv.mapdb_day_pass_sack or "(not set)"))
        respond("           stop for dead: " .. (state.stop_for_dead and "on" or "off"))
        respond("         vaalor shortcut: " .. (state.vaalor_shortcut and "on" or "off"))
        respond("             FWI trinket: " .. (uv.mapdb_fwi_trinket ~= "" and uv.mapdb_fwi_trinket or "(not set)"))
        respond("          caravan to sos: " .. (uv.mapdb_car_to_sos and "on" or "off"))
        respond("        caravan from sos: " .. (uv.mapdb_car_from_sos and "on" or "off"))
        respond("     use gigas fragments: " .. (state.use_gigas_hwtravel and "on" or "off"))
        respond("    min gigas before use: " .. (state.gigas_min_number or 4))
    end
    if is_plat() or is_shattered() then
        respond("             use portals: " .. (uv.mapdb_use_portals and "yes" or "no"))
    end
    if is_plat() then
        respond("         use old portals: " .. (uv.mapdb_use_old_portals and "yes" or "no"))
        respond("        have portal pass: " .. (uv.mapdb_have_portal_pass and "yes" or "no"))
    end
    respond("")
    respond("custom targets:")
    respond("")
    local targets = settings.load_targets()
    for name, val in pairs(targets) do
        local display
        if type(val) == "table" then
            display = table.concat(val, ", ")
        else
            local room = Map.find_room(val)
            local title = room and (type(room.title) == "table" and room.title[1] or room.title) or "?"
            display = tostring(val) .. " - " .. title
        end
        respond("   " .. string.format("%-16s", name) .. " = " .. display)
    end
    respond("")
end

-------------------------------------------------------------------------------
-- Command: targets
-------------------------------------------------------------------------------

local function show_targets()
    respond("[go2] Generating target list...")
    local interesting_gs = {
        "advguard", "advguard2", "advguild", "advpickup", "alchemist",
        "armorshop", "bakery", "bank", "bardguild", "boutique", "chronomage",
        "clericguild", "clericshop", "cobbling", "collectibles", "consignment",
        "empathguild", "exchange", "fletcher", "forge", "furrier", "gemshop",
        "general store", "grocer", "herbalist", "inn", "locksmith pool",
        "locksmith", "mail", "movers", "npccleric", "npchealer", "pawnshop",
        "portmaster", "postoffice", "public locker", "rangerguild", "smokeshop",
        "sorcererguild", "sunfist", "town", "treasuremaster", "voln",
        "warriorguild", "weaponshop", "wizardguild",
    }
    local interesting_dr = {
        "alchemist", "armorshop", "bakery", "bank", "barbarian", "bard",
        "boutique", "cleric", "clericshop", "empath", "exchange", "fletcher",
        "forge", "furrier", "gemshop", "general store", "herbalist", "inn",
        "locksmith", "moonmage", "movers", "necromancer", "npchealer",
        "paladin", "pawnshop", "private forge", "ranger", "smokeshop",
        "stable", "thief", "town", "trader", "warmage", "weaponshop",
    }
    local interesting = is_dr() and interesting_dr or interesting_gs

    -- Index rooms by tag
    local by_tag = {}
    local all_ids = Map.list()
    for _, id in ipairs(all_ids) do
        local r = Map.find_room(id)
        if r and r.tags then
            for _, t in ipairs(r.tags) do
                if not by_tag[t] then by_tag[t] = {} end
                by_tag[t][#by_tag[t] + 1] = id
            end
        end
    end

    -- Group by nearest town
    local town_ids = by_tag["town"] or {}
    local town_data = {}
    for _, tid in ipairs(town_ids) do
        local tr = Map.find_room(tid)
        if tr and not (tr.tags and table.concat(tr.tags, " "):find("closed")) then
            town_data[#town_data + 1] = { id = tid, room = tr }
        end
    end

    local town_map = {}
    for _, td in ipairs(town_data) do town_map[td.id] = {} end

    for _, tag in ipairs(interesting) do
        local rooms = by_tag[tag]
        if rooms then
            for _, rid in ipairs(rooms) do
                -- find nearest town
                local best_tid, best_steps = nil, math.huge
                for _, td in ipairs(town_data) do
                    local p = Map.find_path(rid, td.id)
                    if p and #p < best_steps then
                        best_steps = #p
                        best_tid = td.id
                    end
                end
                if best_tid and town_map[best_tid] then
                    local rr = Map.find_room(rid)
                    local title = rr and (type(rr.title) == "table" and rr.title[1] or rr.title) or "Room " .. rid
                    local line = string.format(" - %-17s %-34s - %5d", tag, title:sub(1, 34), rid)
                    -- deduplicate same tag
                    local found = false
                    for _, existing in ipairs(town_map[best_tid]) do
                        if existing:find(tag, 1, true) and existing:find(tostring(rid)) then
                            found = true; break
                        end
                    end
                    if not found then
                        town_map[best_tid][#town_map[best_tid] + 1] = line
                    end
                end
            end
        end
    end

    for _, td in ipairs(town_data) do
        respond("---------------------------------------------------------------")
        local loc = td.room.location or ""
        loc = loc:gsub("^.*([A-Z].-)$", "%1")
        respond(string.format(" - %-17s %-34s - %5d", "town", loc:sub(1, 34), td.id))
        respond("---------------------------------------------------------------")
        table.sort(town_map[td.id])
        for _, line in ipairs(town_map[td.id]) do
            respond(line)
        end
        respond("")
    end

    if is_dr() then
        respond("---------------------------------------------------------------")
        respond(" - Known Nexus Rooms")
        respond("---------------------------------------------------------------")
        for _, id in ipairs(by_tag["nexus"] or {}) do
            local r = Map.find_room(id)
            local title = r and (type(r.title) == "table" and r.title[1] or r.title) or "Room " .. id
            respond(string.format("%-45s - %5d", title:sub(1, 45), id))
        end
    end
end

-------------------------------------------------------------------------------
-- Command: save
-------------------------------------------------------------------------------

local function handle_save(target_search_string)
    -- Formats: "save name=1234" or "save name=[1234, 5678]" or "save name=current"
    local name, val_str = target_search_string:match("^save%s+(.-)%s*=%s*(.+)$")
    if not name or not val_str then
        respond("[go2] Usage: ;go2 save <name>=<room_id|current>")
        respond("[go2]    or: ;go2 save <name>=[1234,5678]")
        return
    end
    name = name:match("^%s*(.-)%s*$")
    if name:match("^%d+$") or name == "" then
        respond("[go2] Error: target name cannot be only digits or empty")
        return
    end

    -- Parse value: bracket array, single number, or "current"
    local ids = {}
    local inner = val_str:match("^%[(.+)%]$") or val_str
    for part in inner:gmatch("[^,]+") do
        local p = part:match("^%s*(.-)%s*$")
        if p:lower() == "current" then
            local cur = Map.current_room()
            if not cur then
                respond("[go2] Error: current room not in map database")
                return
            end
            ids[#ids + 1] = cur
        elseif p:match("^[uU]%d+$") then
            -- UID: resolve to LichID
            local uid_str = p:match("^[uU](%d+)$")
            local resolved = nil
            if Map.ids_from_uid then
                local list = Map.ids_from_uid(tonumber(uid_str))
                if list and list[1] then resolved = list[1] end
            end
            if not resolved then
                respond("[go2] Error: UID " .. p .. " not found in map database")
                return
            end
            ids[#ids + 1] = resolved
        else
            local n = tonumber(p)
            if not n then
                respond("[go2] Error: invalid room ID: " .. p)
                return
            end
            ids[#ids + 1] = n
        end
    end

    -- Validate all IDs
    for _, id in ipairs(ids) do
        if not Map.find_room(id) then
            respond("[go2] Error: room " .. id .. " not found in map database")
            return
        end
    end

    local targets = settings.load_targets()
    local existing = targets[name]

    local final_val
    if #ids == 1 then
        if type(existing) == "table" then
            -- Append
            existing[#existing + 1] = ids[1]
            -- Deduplicate
            local seen = {}
            local uniq = {}
            for _, v in ipairs(existing) do
                if not seen[v] then seen[v] = true; uniq[#uniq + 1] = v end
            end
            final_val = #uniq == 1 and uniq[1] or uniq
            respond("[go2] Appended to existing array target '" .. name .. "'")
        elseif type(existing) == "number" then
            if existing == ids[1] then
                final_val = existing
            else
                respond("[go2] Custom target '" .. name .. "' exists. Replacing with: " .. ids[1])
                final_val = ids[1]
            end
        else
            final_val = ids[1]
        end
    else
        final_val = ids
    end

    targets[name] = final_val
    settings.save_targets(targets)
    local display = type(final_val) == "table" and ("[" .. table.concat(final_val, ", ") .. "]") or tostring(final_val)
    respond("[go2] Custom target saved: " .. name .. " => " .. display)
end

-------------------------------------------------------------------------------
-- Command: delete
-------------------------------------------------------------------------------

local function handle_delete(target_search_string)
    local delkey = target_search_string:match("^delete%s+(.+)$")
    if not delkey then
        respond("[go2] Usage: ;go2 delete <name>")
        return
    end
    delkey = delkey:match("^%s*(.-)%s*$")
    local targets = settings.load_targets()
    -- Exact match first, then prefix
    local kilkey = targets[delkey] and delkey
    if not kilkey then
        local dl = delkey:lower()
        for name in pairs(targets) do
            if name:lower():find("^" .. dl) then kilkey = name; break end
        end
    end
    if kilkey then
        targets[kilkey] = nil
        settings.save_targets(targets)
        respond("[go2] Custom target deleted: " .. kilkey)
    else
        respond("[go2] '" .. delkey .. "' is not a saved custom target")
    end
end

-------------------------------------------------------------------------------
-- Urchin expiry check/update
-------------------------------------------------------------------------------

local function update_urchin_expire()
    if not uv.mapdb_use_urchins then return end
    fput("urchin status")
    local result = matchwait(
        "You will have access to the urchin guides until",
        "You currently have no access to the urchin guides",
        "permanent access to the urchin guides"
    )
    if result and result:find("permanent access") then
        -- Set expire 1 year from now
        settings.set_urchin_expire(os.time() + 365 * 24 * 3600)
        echo("[go2] Urchin expiration: permanent")
    elseif result then
        local expires_str = result:match("until%s+(.-)%.")
        if expires_str then
            -- os.time from date string is complex in Lua; approximate via raw storage
            settings.set_urchin_expire(os.time() + 86400)  -- assume at least 1 day
            echo("[go2] Urchin expiry updated")
        else
            settings.set_urchin_expire(0)
        end
    else
        settings.set_urchin_expire(0)
    end
    if uv.mapdb_use_urchins and not settings.urchins_active() then
        echo("[go2] Urchin access appears expired. Disable with ;go2 --use-urchins=off")
    end
end

-------------------------------------------------------------------------------
-- Silver utilities (GS only)
-------------------------------------------------------------------------------

local function check_silvers()
    local result = dothistimeout("wealth quiet", 3,
        "^You have (?:no|[,%d]+|but one) silver with you")
    if not result then return 0 end
    result = result:gsub("but one", "1")
    local coins = result:match("[,%d]+")
    if not coins then return 0 end
    return tonumber(coins:gsub(",", "")) or 0
end

local function get_gigas_fragment_count()
    local result = dothistimeout("wealth gigas", 5,
        "You are carrying %d+ gigas artifact fragments%.")
    if not result then return 0 end
    local n = result:match("carrying (%d+) gigas artifact fragments")
    return tonumber(n) or 0
end

-------------------------------------------------------------------------------
-- Hinterwilds gigas travel (GS only)
-------------------------------------------------------------------------------

-- Room IDs that mark the HW boundary in the path
local HW_ROOM_EN   = 13205202  -- Elven side approach (uid)
local HW_ROOM_IM   = 4132054   -- Imaera's Motte approach (uid)
local HW_ROOM_HW   = 7503253   -- HW portal room (uid)
local HW_PATH_IDS  = { 29860, 22154 }  -- LichIDs that appear in cross-HW paths

local function path_crosses_hinterwilds(path_commands)
    -- Heuristic: check if any room in the path sequence has HW-boundary ids
    -- We walk the map via get_path_rooms and check location fields
    local from_id = Map.current_room()
    if not from_id then return false end
    local rooms = pathfinder.get_path_rooms(from_id, path_commands)
    for _, id in ipairs(rooms) do
        for _, hw_id in ipairs(HW_PATH_IDS) do
            if id == hw_id then return true end
        end
    end
    return false
end

local function hinterwilds_travel(dest_id, path_commands)
    local from_id  = Map.current_room()
    local from_loc = from_id and Map.find_room(from_id) and Map.find_room(from_id).location or ""
    local to_room  = Map.find_room(dest_id)
    local to_loc   = to_room and to_room.location or ""

    local heading_to_hw = to_loc == "the Hinterwilds"

    if heading_to_hw then
        -- Determine approach side by checking room titles in path
        local rooms = pathfinder.get_path_rooms(from_id, path_commands)
        local via_en = false
        for _, id in ipairs(rooms) do
            local r = Map.find_room(id)
            if r and r.title then
                local title = type(r.title) == "table" and r.title[1] or r.title
                if title and title:find("Seethe Naedal") then
                    via_en = true; break
                end
            end
        end
        local transport = via_en and ("u" .. HW_ROOM_EN) or ("u" .. HW_ROOM_IM)
        settings.set_uvar("mapdb_hinterwilds_location", via_en and "EN" or "IM")
        Script.run("go2", transport)
        while running("go2") do pause(0.5) end
        pause(0.5)
        fput("go sliver")
        pause(1.0)
    else
        -- Leaving HW: navigate to the HW portal room then order transport
        Script.run("go2", "u" .. HW_ROOM_HW)
        while running("go2") do pause(0.5) end
        pause(0.5)
        fput("order 3")
        fput("order confirm")
        pause(1.0)
    end
    settings.set_uvar("mapdb_hinterwilds_location", nil)
end

-------------------------------------------------------------------------------
-- Playershop escape (GS only)
-------------------------------------------------------------------------------

local function playershop_escape()
    local exits = GameState.room_exits
    if not exits then return end
    local exits_str = type(exits) == "table" and table.concat(exits, " ") or tostring(exits)
    if not exits_str:find("Obvious exits:") then return end

    local suffixes = {
        "Outfitting", "Magic Shoppe", "Weaponry", "General Store",
        "Armory", "Combat Gear", "Lockpicks",
    }
    local uid_groups = { 631, 632, 633, 634, 635, 636, 637, 638, 639, 640, 641, 642, 643, 644, 645, 646 }
    local room_name  = GameState.room_name or ""
    local room_id    = GameState.room_id or 0

    local in_playershop = false
    for _, suf in ipairs(suffixes) do
        if room_name:find(suf) then in_playershop = true; break end
    end
    if not in_playershop then
        local group = math.floor(room_id / 1000)
        for _, g in ipairs(uid_groups) do
            if group == g then in_playershop = true; break end
        end
    end

    if in_playershop then
        local has_out = false
        if type(exits) == "table" then
            for _, e in ipairs(exits) do if e == "out" then has_out = true; break end end
        end
        if not has_out then
            local first_exit = type(exits) == "table" and exits[1] or nil
            if first_exit then move(first_exit) end
        end
        move("out")
    end
end

-------------------------------------------------------------------------------
-- Main CLI option parsing and settings-only save
-------------------------------------------------------------------------------

local setting_typeahead          = opt_num("typeahead", nil)
local setting_delay              = opt_num("delay", nil)
local setting_disable_confirm    = opt_bool("disable-confirm", nil)
local setting_hide_desc          = opt_bool("hide-room-descriptions", nil) or opt_bool("hide-desc", nil)
local setting_hide_titles        = opt_bool("hide-room-titles", nil) or opt_bool("hide-titles", nil)
local setting_echo_input         = opt_bool("echo-input", nil)

-- GS-specific
local setting_get_silvers        = is_gs() and opt_bool("get-silvers", nil) or nil
local setting_get_return_silvers = is_gs() and opt_bool("get-return-trip-silvers", nil) or nil
local setting_ice_mode           = is_gs() and opt_str("ice-mode", nil) or nil
local setting_stop_for_dead      = opt_bool("stop-for-dead", nil)
local setting_vaalor_shortcut    = is_gs() and opt_bool("shortcut", nil) or nil
local setting_use_seeking        = is_gs() and opt_bool("use-seeking", nil) or nil
local setting_use_urchins        = is_gs() and opt_bool("use-urchins", nil) or nil
local setting_use_portmasters    = is_gs() and opt_bool("use-portmasters", nil) or nil
local setting_use_day_pass       = is_gs() and opt_bool("use-day-pass", nil) or nil
local setting_buy_day_pass       = is_gs() and opt_str("buy-day-pass", nil) or nil
local setting_day_pass_container = is_gs() and opt_str("day-pass-container", nil) or nil
local setting_fwi_trinket        = is_gs() and opt_str("fwi-trinket", nil) or nil
local setting_car_to_sos         = is_gs() and opt_bool("caravan-to-sos", nil) or nil
local setting_car_from_sos       = is_gs() and opt_bool("caravan-from-sos", nil) or nil
local setting_use_gigas          = is_gs() and opt_bool("use-gigas-hwtravel", nil) or nil
local setting_gigas_min          = is_gs() and opt_num("gigas-min-number", nil) or nil
local setting_instability        = is_gs() and opt_num("instability", nil) or nil
-- Plat/Shattered
local setting_use_portals        = (is_plat() or is_shattered()) and opt_bool("portals", nil) or nil
local setting_use_old_portals    = is_plat() and opt_bool("old-portals", nil) or nil
local setting_portal_pass        = is_plat() and opt_bool("portal-pass", nil) or nil
-- DR
local setting_drag               = is_dr() and opt_str("drag", nil) or nil

-- Build target search string from remaining positional args
local target_search_string = table.concat(args_raw, " ")

-------------------------------------------------------------------------------
-- Non-navigation commands
-------------------------------------------------------------------------------

local function dispatch_command(cmd)
    if cmd == "" or cmd == "help" then
        show_help()
        return true
    elseif cmd == "setup" then
        local gui = require("gui_settings")
        local targets = settings.load_targets()
        gui.open(state, uv, targets)
        return true
    elseif cmd == "list" then
        show_list()
        return true
    elseif cmd == "targets" then
        show_targets()
        return true
    elseif cmd:find("^save%s") then
        handle_save(cmd)
        return true
    elseif cmd:find("^delete%s") then
        handle_delete(cmd)
        return true
    elseif cmd == "reload" then
        Map.reload()
        echo("[go2] Map data reloaded")
        return true
    end
    return false
end

if dispatch_command(target_search_string:lower()) then
    return
end

-- Echo input if configured
if state.echo_input then
    echo("[go2] input: " .. raw_vars)
end

-------------------------------------------------------------------------------
-- Settings-only mode: save options and exit if no target
-------------------------------------------------------------------------------

local has_target = target_search_string ~= ""

-- Apply option flags and save if no target
local function apply_and_save_option(cond, char_key, uvar_key, value, msg)
    if not cond then return end
    if char_key then
        state[char_key] = value
    end
    if uvar_key then
        uv[uvar_key] = value
    end
    if msg then echo("[go2] " .. msg) end
end

local function save_all_options()
    if setting_typeahead then
        state.typeahead = setting_typeahead
        echo("[go2] typeahead → " .. setting_typeahead)
    end
    if setting_delay then
        state.delay = setting_delay
        echo("[go2] delay → " .. setting_delay .. "s")
    end
    if setting_hide_desc ~= nil then
        state.hide_room_descriptions = setting_hide_desc
        echo("[go2] hide room descriptions → " .. (setting_hide_desc and "on" or "off"))
    end
    if setting_hide_titles ~= nil then
        state.hide_room_titles = setting_hide_titles
        echo("[go2] hide room titles → " .. (setting_hide_titles and "on" or "off"))
    end
    if setting_echo_input ~= nil then
        state.echo_input = setting_echo_input
        echo("[go2] echo input → " .. (setting_echo_input and "on" or "off"))
    end
    if setting_stop_for_dead ~= nil then
        state.stop_for_dead = setting_stop_for_dead
        echo("[go2] stop for dead → " .. (setting_stop_for_dead and "on" or "off"))
    end
    if setting_disable_confirm ~= nil then
        state.disable_confirm = setting_disable_confirm
        echo("[go2] disable confirm → " .. (setting_disable_confirm and "on" or "off"))
    end
    -- GS
    if setting_get_silvers ~= nil then
        state.get_silvers = setting_get_silvers
        echo("[go2] get silvers → " .. (setting_get_silvers and "on" or "off"))
    end
    if setting_get_return_silvers ~= nil then
        state.get_return_silvers = setting_get_return_silvers
        echo("[go2] get return trip silvers → " .. (setting_get_return_silvers and "on" or "off"))
    end
    if setting_ice_mode then
        uv.mapdb_ice_mode = setting_ice_mode
        echo("[go2] ice mode → " .. setting_ice_mode)
    end
    if setting_vaalor_shortcut ~= nil then
        state.vaalor_shortcut = setting_vaalor_shortcut
        echo("[go2] vaalor shortcut → " .. (setting_vaalor_shortcut and "on" or "off"))
    end
    if setting_use_seeking ~= nil then
        state.use_seeking = setting_use_seeking
        echo("[go2] use seeking → " .. (setting_use_seeking and "on" or "off"))
    end
    if setting_use_urchins ~= nil then
        uv.mapdb_use_urchins = setting_use_urchins
        echo("[go2] use urchins → " .. (setting_use_urchins and "on" or "off"))
    end
    if setting_use_portmasters ~= nil then
        uv.mapdb_use_portmasters = setting_use_portmasters
        echo("[go2] use portmasters → " .. (setting_use_portmasters and "on" or "off"))
    end
    if setting_use_day_pass ~= nil then
        uv.mapdb_use_day_pass = setting_use_day_pass
        echo("[go2] use day pass → " .. (setting_use_day_pass and "on" or "off"))
    end
    if setting_buy_day_pass then
        uv.mapdb_buy_day_pass = setting_buy_day_pass
        echo("[go2] buy day pass setting saved")
    end
    if setting_day_pass_container then
        uv.mapdb_day_pass_sack = setting_day_pass_container
        echo("[go2] day pass container → " .. setting_day_pass_container)
    end
    if setting_fwi_trinket then
        if setting_fwi_trinket:lower() == "off" then
            uv.mapdb_fwi_trinket = ""
            echo("[go2] FWI trinket disabled")
        else
            uv.mapdb_fwi_trinket = setting_fwi_trinket
            echo("[go2] FWI trinket → " .. setting_fwi_trinket)
        end
    end
    if setting_car_to_sos ~= nil then
        uv.mapdb_car_to_sos = setting_car_to_sos
        echo("[go2] caravan to SoS → " .. (setting_car_to_sos and "on" or "off"))
    end
    if setting_car_from_sos ~= nil then
        uv.mapdb_car_from_sos = setting_car_from_sos
        echo("[go2] caravan from SoS → " .. (setting_car_from_sos and "on" or "off"))
    end
    if setting_use_gigas ~= nil then
        state.use_gigas_hwtravel = setting_use_gigas
        echo("[go2] use gigas hwtravel → " .. (setting_use_gigas and "on" or "off"))
    end
    if setting_gigas_min then
        local clamped = math.max(4, math.min(20, setting_gigas_min))
        state.gigas_min_number = clamped
        echo("[go2] min gigas before use → " .. clamped)
    end
    if setting_use_portals ~= nil then
        uv.mapdb_use_portals = setting_use_portals
        echo("[go2] use portals → " .. (setting_use_portals and "yes" or "no"))
    end
    if setting_use_old_portals ~= nil then
        uv.mapdb_use_old_portals = setting_use_old_portals
        echo("[go2] use old portals → " .. (setting_use_old_portals and "yes" or "no"))
    end
    if setting_portal_pass ~= nil then
        uv.mapdb_have_portal_pass = setting_portal_pass
        echo("[go2] have portal pass → " .. (setting_portal_pass and "yes" or "no"))
    end
    -- Persist
    settings.save(state)
    settings.save_uservars(uv)
end

if not has_target then
    save_all_options()
    return
end

-------------------------------------------------------------------------------
-- Navigation mode
-- Apply per-run overrides (without persisting them) and restore on exit
-------------------------------------------------------------------------------

-- Snapshot current values for before_dying restore
local restore = {}
local function run_override(char_key, uvar_key, value)
    if char_key and value ~= nil then
        restore[char_key] = state[char_key]
        state[char_key] = value
    end
    if uvar_key and value ~= nil then
        restore["_uv_" .. uvar_key] = uv[uvar_key]
        uv[uvar_key] = value
        -- Also set the engine UserVar so stringprocs see it
        UserVars[uvar_key] = value
    end
end

-- Apply all per-run option overrides
if setting_delay ~= nil        then run_override("delay", nil, setting_delay) end
if setting_typeahead ~= nil    then run_override("typeahead", nil, setting_typeahead) end
if setting_hide_desc ~= nil    then run_override("hide_room_descriptions", nil, setting_hide_desc) end
if setting_hide_titles ~= nil  then run_override("hide_room_titles", nil, setting_hide_titles) end
if setting_echo_input ~= nil   then run_override("echo_input", nil, setting_echo_input) end
if setting_stop_for_dead ~= nil then run_override("stop_for_dead", nil, setting_stop_for_dead) end
if setting_disable_confirm ~= nil then run_override("disable_confirm", nil, setting_disable_confirm) end
if setting_drag ~= nil         then run_override("drag", nil, setting_drag) end
-- GS overrides
if is_gs() then
    if setting_get_silvers ~= nil    then run_override("get_silvers", nil, setting_get_silvers) end
    if setting_get_return_silvers ~= nil then run_override("get_return_silvers", nil, setting_get_return_silvers) end
    if setting_vaalor_shortcut ~= nil then run_override("vaalor_shortcut", nil, setting_vaalor_shortcut) end
    if setting_use_seeking ~= nil    then run_override("use_seeking", nil, setting_use_seeking) end
    if setting_use_gigas ~= nil      then run_override("use_gigas_hwtravel", nil, setting_use_gigas) end
    if setting_gigas_min ~= nil      then run_override("gigas_min_number", nil, math.max(4, math.min(20, setting_gigas_min))) end
    if setting_use_urchins ~= nil    then run_override(nil, "mapdb_use_urchins", setting_use_urchins) end
    if setting_use_portmasters ~= nil then run_override(nil, "mapdb_use_portmasters", setting_use_portmasters) end
    if setting_use_day_pass ~= nil   then run_override(nil, "mapdb_use_day_pass", setting_use_day_pass) end
    if setting_buy_day_pass ~= nil   then run_override(nil, "mapdb_buy_day_pass", setting_buy_day_pass) end
    if setting_day_pass_container ~= nil then run_override(nil, "mapdb_day_pass_sack", setting_day_pass_container) end
    if setting_ice_mode              then run_override(nil, "mapdb_ice_mode", setting_ice_mode) end
    if setting_fwi_trinket then
        local v = setting_fwi_trinket:lower() == "off" and "" or setting_fwi_trinket
        run_override(nil, "mapdb_fwi_trinket", v)
    end
    if setting_car_to_sos ~= nil     then run_override(nil, "mapdb_car_to_sos", setting_car_to_sos) end
    if setting_car_from_sos ~= nil   then run_override(nil, "mapdb_car_from_sos", setting_car_from_sos) end
end
if setting_use_portals ~= nil   then run_override(nil, "mapdb_use_portals", setting_use_portals) end
if setting_use_old_portals ~= nil then run_override(nil, "mapdb_use_old_portals", setting_use_old_portals) end
if setting_portal_pass ~= nil   then run_override(nil, "mapdb_have_portal_pass", setting_portal_pass) end

-- Restore on exit
before_dying(function()
    pathfinder.clear_blacklist()
    movement.reset_mounted()
    -- Restore overridden UserVars
    for k, v in pairs(restore) do
        if k:find("^_uv_") then
            local uv_key = k:sub(5)
            UserVars[uv_key] = v
        end
    end
end)

-- Ensure UserVars match our uv table for this run (stringprocs check them)
for k in pairs(settings.USERVARS_DEFAULTS) do
    if uv[k] ~= nil then
        UserVars[k] = uv[k]
    end
end

-------------------------------------------------------------------------------
-- Urchin expire check
-------------------------------------------------------------------------------

if is_gs() and uv.mapdb_use_urchins and not settings.urchins_active() then
    -- Spawn expire update in background (non-blocking)
    -- We update the expire so future runs benefit; don't block navigation
    before_dying(update_urchin_expire)
end

-------------------------------------------------------------------------------
-- Playershop escape (GS only)
-------------------------------------------------------------------------------

if is_gs() and not Map.current_room() then
    playershop_escape()
end

-------------------------------------------------------------------------------
-- Current room check
-------------------------------------------------------------------------------

local start_room = Map.current_room()
if not start_room then
    respond("[go2] Error: current room not found in map database")
    return
end

-- Save start room for goback
settings.save_start_room(start_room)

-------------------------------------------------------------------------------
-- Resolve destination
-------------------------------------------------------------------------------

local dest_id, confirm, resolve_err = resolver.resolve(target_search_string, start_room)
if not dest_id then
    respond("[go2] Error: " .. (resolve_err or "unknown target"))
    return
end

if start_room == dest_id then
    respond("[go2] You're already there...")
    return
end

-------------------------------------------------------------------------------
-- Hooks: hide descriptions/titles
-------------------------------------------------------------------------------

if state.hide_room_descriptions then
    put("flag description off")
    before_dying(function()
        put("flag description on")
        put("look")
    end)
end

if state.hide_room_titles then
    put("flag roomnames off")
    before_dying(function()
        put("flag roomnames on")
        put("look")
    end)
end

-- Stop-for-dead hook
local go2_see_dead = false
if state.stop_for_dead then
    DownstreamHook.add("go2_dead_watch", function(line)
        if line:find("the body of") then go2_see_dead = true end
        return line
    end)
    before_dying(function() DownstreamHook.remove("go2_dead_watch") end)
end

-------------------------------------------------------------------------------
-- Silver cost check (GS only)
-------------------------------------------------------------------------------

local function check_and_get_silvers(path_cmds)
    if not is_gs() then return true end

    local needed = pathfinder.estimate_silver_cost(start_room, dest_id)
    if state.get_return_silvers then
        local return_cmds = Map.find_path(dest_id, start_room)
        if return_cmds then
            needed = needed + pathfinder.estimate_silver_cost(dest_id, start_room)
        end
    end
    if needed <= 0 then return true end

    local have = check_silvers()
    if have >= needed then return true end

    if not state.get_silvers then
        echo("[go2] Warning: you may not have enough silver for this trip (" .. needed .. " needed, " .. have .. " on hand)")
        echo("[go2] Use ;go2 --get-silvers=on to allow bank withdrawal")
        echo("[go2] Continuing anyway in 10 seconds...")
        pause(10)
        return true
    end

    -- Navigate to bank, withdraw, continue
    local bank_result = Map.find_nearest_by_tag("bank")
    if not bank_result or not bank_result.id then
        respond("[go2] Error: no bank found — you need " .. needed .. " silver but only have " .. have)
        return false
    end
    local bank_id = bank_result.id

    local _, bank_path_cost = pathfinder.estimate_silver_cost(start_room, bank_id), nil
    if have < (bank_path_cost or 0) then
        respond("[go2] Error: too poor to even reach the bank")
        return false
    end

    respond("[go2] Insufficient silver (" .. have .. "/" .. needed .. "). Navigating to bank [" .. bank_id .. "]...")

    local bank_cmds = Map.find_path(start_room, bank_id)
    if not bank_cmds then
        respond("[go2] Error: no path to bank found")
        return false
    end

    local walk_fn = (state.typeahead or 0) > 0 and movement.walk_typeahead or movement.walk
    local ok, werr = walk_fn(bank_cmds, state, nil)
    if not ok then
        respond("[go2] Error reaching bank: " .. tostring(werr))
        return false
    end

    -- Withdraw
    if hidden() or invisible() then fput("unhide") end
    local withdraw_amount = needed - check_silvers()
    if withdraw_amount > 0 then
        local bank_room = Map.find_room(Map.current_room())
        local bank_title = bank_room and (type(bank_room.title) == "table" and bank_room.title[1] or bank_room.title) or ""
        if bank_title:find("Depository") or bank_title:find("Pinefar") then
            fput("ask banker for " .. math.max(withdraw_amount, 20) .. " silvers")
        else
            fput("withdraw " .. withdraw_amount .. " silvers")
        end
        pause(1)
    end

    local now_have = check_silvers()
    if now_have < needed then
        respond("[go2] Error: still not enough silver after bank visit (" .. now_have .. "/" .. needed .. ")")
        return false
    end

    -- Re-establish start room after bank trip
    start_room = Map.current_room()
    return true
end

if not check_and_get_silvers(nil) then return end

-------------------------------------------------------------------------------
-- Vaalor shortcut: adjust map timeto
-------------------------------------------------------------------------------

local function apply_vaalor_shortcut(enabled)
    if not is_gs() then return end
    local r16745 = Map.find_room(16745)
    local r16746 = Map.find_room(16746)
    if not r16745 or not r16746 then return end
    -- Only modify if not already a proc-based timeto
    if enabled then
        if r16745.timeto and not r16745.timeto["16746"] then
            r16745.timeto["16746"] = 15
        end
        if r16746.timeto and not r16746.timeto["16745"] then
            r16746.timeto["16745"] = 15
        end
    else
        if r16745.timeto then r16745.timeto["16746"] = nil end
        if r16746.timeto then r16746.timeto["16745"] = nil end
    end
end

if is_gs() then
    apply_vaalor_shortcut(state.vaalor_shortcut)
    before_dying(function() apply_vaalor_shortcut(false) end)
end

-------------------------------------------------------------------------------
-- Path calculation and ETA
-------------------------------------------------------------------------------

local function compute_path(from_id, to_id)
    local cmds = Map.find_path(from_id, to_id)
    if not cmds then return nil, "no path found from " .. from_id .. " to " .. to_id end
    return cmds, nil
end

local path_cmds, path_err = compute_path(start_room, dest_id)
if not path_cmds then
    respond("[go2] Error: " .. path_err)
    return
end
local steps = #path_cmds

-- Check Hinterwilds gigas travel
if is_gs() and state.use_gigas_hwtravel and path_crosses_hinterwilds(path_cmds) then
    local frag_count = get_gigas_fragment_count()
    if frag_count >= (state.gigas_min_number or 4) then
        echo("[go2] Using gigas fragments for Hinterwilds travel (" .. frag_count .. " fragments)")
        hinterwilds_travel(dest_id, path_cmds)
        -- Re-compute path from new location
        start_room = Map.current_room()
        if not start_room then
            respond("[go2] Error: lost position after Hinterwilds transport")
            return
        end
        if start_room == dest_id then
            respond("[go2] Arrived at destination (via Hinterwilds transport)")
            return
        end
        path_cmds, path_err = compute_path(start_room, dest_id)
        if not path_cmds then
            respond("[go2] Error: " .. path_err)
            return
        end
        steps = #path_cmds
    end
end

-- Confirmation for long/unfamiliar destinations
local dest_room = Map.find_room(dest_id)
local dest_title = dest_room and (type(dest_room.title) == "table" and dest_room.title[1] or dest_room.title) or ("Room " .. dest_id)

if confirm and not state.disable_confirm then
    respond("[go2] Destination: " .. dest_title .. " [" .. dest_id .. "] — " .. steps .. " steps")
    respond("[go2] To go here, unpause the script. To abort, kill the script.")
    pause(999999)
end

respond("[go2] ETA: ~" .. steps .. " moves to: " .. dest_title .. " [" .. dest_id .. "]")

-------------------------------------------------------------------------------
-- Navigation loop
-------------------------------------------------------------------------------

local start_time  = os.time()
local max_retries = 5
local retries     = 0

while retries < max_retries do
    local cur = Map.current_room()
    if not cur then
        respond("[go2] Error: lost position — current room not in map database")
        break
    end

    if cur == dest_id then
        break
    end

    -- Re-compute path if needed
    if cur ~= start_room then
        path_cmds, path_err = compute_path(cur, dest_id)
        if not path_cmds then
            respond("[go2] Error: " .. path_err)
            break
        end
        start_room = cur
    end

    if #path_cmds == 0 then break end

    local walk_fn = (state.typeahead or 0) > 0 and movement.walk_typeahead or movement.walk

    local ok, walk_err = walk_fn(path_cmds, state, function(i, total, cmd_str)
        -- Stop-for-dead callback
        if go2_see_dead then
            local pcs = GameObj.pcs()
            local dead_pc = false
            if pcs then
                for _, pc in ipairs(pcs) do
                    if pc.status and pc.status:find("dead") then dead_pc = true; break end
                end
            end
            if dead_pc then
                respond("[go2] Dead body detected — pausing. ;unpause go2 to continue.")
                go2_see_dead = false
                pause(999999)
            else
                go2_see_dead = false
            end
        end
    end)

    if ok or cur == dest_id then
        break
    elseif walk_err == "dead" then
        respond("[go2] You have died — navigation stopped")
        return
    elseif walk_err and walk_err:find("^manual:") then
        local to_str = walk_err:match("^manual:%d+:(%d+)$")
        local to_id = tonumber(to_str)
        local manual_room = to_id and Map.find_room(to_id)
        respond("[go2] Cannot auto-navigate this exit (StringProc untranslatable)")
        if manual_room then
            local mt = type(manual_room.title) == "table" and manual_room.title[1] or manual_room.title
            respond("[go2] Target: " .. (mt or "Room " .. to_id) .. " [" .. to_id .. "]")
        end
        respond("[go2] Please navigate manually. go2 will resume on next room change.")
        local prev_room = Map.current_room()
        while true do
            pause(0.5)
            local new_room = Map.current_room()
            if new_room and new_room ~= prev_room then
                respond("[go2] Room change detected — resuming navigation")
                break
            end
        end
        retries = retries + 1
    elseif walk_err == "drag_incompatible" then
        respond("[go2] Cannot drag through this exit type — drag mode cancelled")
        state.drag = nil
        retries = retries + 1
    elseif walk_err == "retry" then
        retries = retries + 1
        if retries < max_retries then
            echo("[go2] Movement failed — re-routing (attempt " .. retries .. "/" .. max_retries .. ")")
            pause(0.5)
        end
    else
        respond("[go2] Error: " .. tostring(walk_err))
        break
    end
end

if retries >= max_retries then
    respond("[go2] Error: exceeded maximum retries (" .. max_retries .. ")")
end

-- Wait briefly for room to settle
local settle = os.time() + 1
while Map.current_room() ~= dest_id and os.time() < settle do
    pause(0.1)
end

-- Travel time
local end_time = os.time()
local travel = end_time - start_time
respond(string.format("[go2] Travel time: %d:%02d", math.floor(travel / 60), travel % 60))

-- Restore room title / description display if needed
if state.hide_room_descriptions or state.hide_room_titles then
    put("look")
end
