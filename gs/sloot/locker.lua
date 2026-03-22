--- sloot/locker.lua
-- Locker navigation, box storage, gem stockpile management.
-- Mirrors to_locker, from_locker, locker_boxes, stockpile, raid_stockpile from sloot.lic v3.5.2.

local items_mod = require("sloot/items")
local sacks_mod = require("sloot/sacks")

local M = {}

-- Persistent jar/stockpile tracking (like CharSettings[:jars] in Lich5)
-- Stored as JSON in CharSettings["sloot_jars"]
local function load_jars()
    local raw = CharSettings["sloot_jars"]
    if not raw or raw == "" then return nil end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or nil
end

local function save_jars(jars)
    if jars == nil then
        CharSettings["sloot_jars"] = ""
    else
        CharSettings["sloot_jars"] = Json.encode(jars)
    end
end

local function load_empty_jar_count()
    local raw = CharSettings["sloot_empty_jars"]
    return tonumber(raw) or 0
end

local function save_empty_jar_count(n)
    CharSettings["sloot_empty_jars"] = tostring(n)
end

--- Navigate to the locker room.
-- Returns true if locker is accessible.
function M.to_locker(settings)
    if (settings.locker or "") == "" then
        echo("[SLoot] locker room not set")
        return false
    end
    go2(settings.locker)

    -- Extra navigation steps
    local locker_in = settings.locker_in or ""
    for cmd in locker_in:gmatch("[^,]+") do
        cmd = cmd:match("^%s*(.-)%s*$")
        if cmd ~= "" then move(cmd) end
    end

    -- Enter through opening/curtain
    local entrance = nil
    for _, obj in ipairs(GameObj.loot()) do
        if Regex.test(obj.noun or "", "^(?:opening|curtain)$") then entrance = obj; break end
    end
    for _, obj in ipairs(GameObj.room_desc() or {}) do
        if not entrance and Regex.test(obj.noun or "", "^(?:opening|curtain)$") then entrance = obj; break end
    end
    if entrance then
        move("go " .. entrance.noun)
    else
        echo("[SLoot] error: failed to find locker entrance")
        return false
    end
    return true
end

--- Navigate out of the locker room.
function M.from_locker(settings)
    local exit_obj = nil
    for _, obj in ipairs(GameObj.loot()) do
        if Regex.test(obj.noun or "", "^(?:opening|curtain)$") then exit_obj = obj; break end
    end
    for _, obj in ipairs(GameObj.room_desc() or {}) do
        if not exit_obj and Regex.test(obj.noun or "", "^(?:opening|curtain)$") then exit_obj = obj; break end
    end
    if exit_obj then
        move("go " .. exit_obj.noun)
    else
        echo("[SLoot] error: failed to find locker exit")
    end

    local locker_out = settings.locker_out or ""
    for cmd in locker_out:gmatch("[^,]+") do
        cmd = cmd:match("^%s*(.-)%s*$")
        if cmd ~= "" then move(cmd) end
    end
end

--- Locker box storage routine.
-- @param boxes    array of GameObj boxes to put in locker
-- @param settings settings table
-- @returns true unless locker became full
function M.locker_boxes(boxes, settings)
    if not M.to_locker(settings) then return false end

    local open_res = dothistimeout("open locker", 5, Regex.new('exist=".*?" noun="(?:locker|chest)"'))
    if not open_res then
        echo("[SLoot] error: failed to find locker to open")
        M.from_locker(settings)
        return false
    end

    local locker_full = false
    for _, box in ipairs(boxes) do
        fput("get #" .. box.id)
        local res = dothistimeout("put #" .. box.id .. " in locker", 3,
            Regex.new("in the locker, and it quickly disappears\\."))
        if not res or Regex.test(res, "") == false then
            -- Locker full — stow box back
            locker_full = true
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            if rh and rh.id == box.id then
                items_mod.loot_it({ rh }, {}, settings)
            elseif lh and lh.id == box.id then
                items_mod.loot_it({ lh }, {}, settings)
            end
            break
        end
    end

    fput("close locker")
    M.from_locker(settings)
    return not locker_full
end

--- Helper: open locker and return {locker_id, contents} or nil
local function open_locker_get_contents()
    local res = dothistimeout("open locker", 5, Regex.new('exist=".*?" noun="(?:locker|chest)"'))
    if not res then return nil end
    local locker_id = res:match('exist="(%d+)" noun="(?:locker|chest)"')
    if not locker_id then return nil end

    -- Get contents
    local containers = GameObj.containers()
    local contents = containers and containers[locker_id]
    if not contents then
        dothistimeout("look in #" .. locker_id, 3, Regex.new("^In the"))
        containers = GameObj.containers()
        contents = containers and containers[locker_id]
    end
    return locker_id, contents
end

--- Determine if stockpiling is needed.
function M.need_to_stockpile(settings)
    local jars = load_jars()
    -- Invalidate if old-style jar names found
    if jars then
        for _, jar in ipairs(jars) do
            if (jar.gem or ""):find("large|medium|small|tiny") then
                save_jars(nil)
                jars = nil
                break
            end
        end
    end

    local lootsack = sacks_mod.sacks["gem"]
    if not lootsack then return false end

    local empty_count = load_empty_jar_count()

    local can_start = empty_count > 0
    if can_start then
        -- Check if any gem in lootsack lacks a matching jar
        for _, obj in ipairs(lootsack.contents or {}) do
            if obj.type and obj.type:find("gem") and not obj.name:find("oblivion quartz$") then
                local base = obj.name:gsub("large |medium |small |tiny |some ", "")
                local has_jar = false
                for _, jar in ipairs(jars or {}) do
                    local pattern = jar.gem:gsub("y$", "(?:y|ie)"):gsub("z$", "ze?"):gsub("%b ", "s? ")
                    if Regex.test(base, "^" .. pattern .. "s?$") then has_jar = true; break end
                end
                if not has_jar then can_start = true; break end
            end
        end
    end

    local can_add = false
    if jars then
        for _, jar in ipairs(jars) do
            if not jar.full then
                for _, obj in ipairs(lootsack.contents or {}) do
                    local pattern = jar.gem:gsub("y$", "(?:y|ie)"):gsub("z$", "ze?"):gsub("%b ", "s? ")
                    if Regex.test(obj.name:gsub("large |medium |small |tiny |some ", ""), "^" .. pattern .. "s?$") then
                        can_add = true; break
                    end
                end
            end
            if can_add then break end
        end
    end

    return (jars == nil) or can_start or can_add
end

--- Check if stockpile can supply the current bounty gem.
function M.need_to_raid_stockpile()
    local task = checkbounty()
    if not task then return false end
    local gem, count_str = task:match("gem dealer.* requesting (?:a|an|some) (.-)\\..*retrieve (%d+) (?:more )?of them\\.")
    if not gem then return false end
    local count = tonumber(count_str) or 0
    local jars = load_jars()
    if not jars then return false end
    local base = gem:gsub("large |medium |small |tiny |some ", "")
    for _, jar in ipairs(jars) do
        local pattern = jar.gem:gsub("y$", "(?:y|ie)"):gsub("z$", "ze?"):gsub("%b ", "s? ")
        if Regex.test(base, "^" .. pattern .. "s?$") and jar.count >= count then
            return true
        end
    end
    return false
end

--- List stockpile jars to echo output.
function M.stockpile_list(filter)
    local jars = load_jars()
    if not jars or #jars == 0 then
        respond("[SLoot] No stockpile recorded.")
        return
    end
    local header = string.format("%-30s %5s  %s", "gem", "count", "full")
    respond(header)
    respond(string.rep("-", 44))
    -- Sort by count descending
    table.sort(jars, function(a, b) return (a.count or 0) > (b.count or 0) end)
    for _, jar in ipairs(jars) do
        if not filter or jar.gem:find(filter) then
            respond(string.format("%-30s %5d  %s", jar.gem, jar.count or 0, tostring(jar.full)))
        end
    end
end

--- Forget the stockpile (;sloot stockpile-forget).
function M.stockpile_forget()
    save_jars(nil)
    save_empty_jar_count(0)
    echo("[SLoot] stockpile cleared")
end

--- Full stockpile gem-in-jars routine (assumes we're in locker room).
function M.stockpile(settings)
    local lootsack = sacks_mod.sacks["gem"]
    if not lootsack then return end

    local locker_id, contents = open_locker_get_contents()
    if not locker_id or not contents then
        dothistimeout("close locker", 3, Regex.new("^You close|already closed"))
        if not locker_id then echo("[SLoot] error: failed to find locker") end
        if not contents then echo("[SLoot] error: failed to find locker contents") end
        return
    end

    local jars = load_jars()
    local empty_count = load_empty_jar_count()

    -- First pass: build jar index if nil
    if jars == nil then
        jars = {}
        empty_count = 0
        for _, jar in ipairs(contents) do
            if Regex.test(jar.noun or "", "^(?:jar|bottle|beaker)$") then
                if not jar.after_name then
                    empty_count = empty_count + 1
                else
                    local look_res = dothistimeout("look in #" .. jar.id .. " from #" .. locker_id, 3,
                        Regex.new("^Inside .*? you see [0-9]+ portion"))
                    if look_res then
                        local cnt = tonumber(look_res:match("you see (%d+) portion")) or 0
                        local gem = (jar.after_name or ""):gsub("^containing |large |medium |small |tiny |some ", "")
                        local full = look_res:find("It is full") ~= nil
                        jars[#jars + 1] = { gem = gem, count = cnt, full = full }
                    end
                end
            end
        end
        save_jars(jars)
        save_empty_jar_count(empty_count)
    end

    empty_hands()
    local not_suitable = {}

    for _, jar in ipairs(contents) do
        if not Regex.test(jar.noun or "", "^(?:jar|beaker|bottle)$") then goto next_jar end

        if jar.after_name and jar.after_name:find("^containing ") then
            -- Partially or newly started jar — find matching gems and add
            local jar_base = (jar.after_name or ""):gsub("^containing |large |medium |small |tiny |some ", "")
            local jar_hash = nil
            for _, jh in ipairs(jars) do
                if jh.gem == jar_base then jar_hash = jh; break end
            end
            if not jar_hash or jar_hash.full then goto next_jar end

            local gem_list = {}
            for _, obj in ipairs(lootsack.contents or {}) do
                if not not_suitable[obj.id] then
                    local obj_base = obj.name:gsub("large |medium |small |tiny |some ", "")
                    local pat = jar_base:gsub("y$", "(?:y|ie)"):gsub("z$", "ze?"):gsub("%b ", "s? ")
                    if Regex.test(obj_base, "^" .. pat .. "s?$") then
                        gem_list[#gem_list + 1] = obj
                    end
                end
            end
            if #gem_list == 0 then goto next_jar end

            dothistimeout("get #" .. jar.id .. " from #" .. locker_id, 3, Regex.new("^You remove"))
            for _, gem in ipairs(gem_list) do
                local result = dothistimeout("_drag #" .. gem.id .. " #" .. jar.id, 3,
                    Regex.new("^You add|is full|does not appear to be a suitable container for"))
                if result and Regex.test(result, "^You add .* filling it") then
                    jar_hash.count = jar_hash.count + 1
                    jar_hash.full = true
                elseif result and Regex.test(result, "^You add") then
                    jar_hash.count = jar_hash.count + 1
                elseif result and Regex.test(result, "is full") then
                    jar_hash.full = true
                    dothistimeout("put #" .. gem.id .. " in #" .. lootsack.id, 3, Regex.new("^You (?:put|tuck|place)"))
                    break
                elseif result and Regex.test(result, "does not appear to be a suitable container for") then
                    not_suitable[gem.id] = true
                    dothistimeout("put #" .. gem.id .. " in #" .. lootsack.id, 3, Regex.new("^You (?:put|tuck|place)"))
                else
                    dothistimeout("put #" .. gem.id .. " in #" .. lootsack.id, 3, Regex.new("^You (?:put|tuck|place)"))
                end
            end
            dothistimeout("put #" .. jar.id .. " in #" .. locker_id, 3, Regex.new("^You (?:put|place)"))

        else
            -- Empty jar — start a new gem type
            if empty_count <= 0 then goto next_jar end

            -- Find most common gem without an existing jar
            local gem_count = {}
            for _, obj in ipairs(lootsack.contents or {}) do
                if obj.type and obj.type:find("gem") and not obj.name:find("oblivion quartz$")
                   and not not_suitable[obj.id] then
                    local base = obj.name:gsub("large |medium |small |tiny |some ", "")
                    -- Skip if already has a jar
                    local has_jar = false
                    for _, jh in ipairs(jars) do
                        local pat = jh.gem:gsub("y$", "(?:y|ie)"):gsub("z$", "ze?"):gsub("%b ", "s? ")
                        if Regex.test(base, "^" .. pat .. "s?$") then has_jar = true; break end
                    end
                    if not has_jar then
                        gem_count[base] = (gem_count[base] or 0) + 1
                    end
                end
            end

            -- Find most common gem
            local best_gem, best_count = nil, 0
            for nm, cnt in pairs(gem_count) do
                if cnt > best_count then best_gem = nm; best_count = cnt end
            end
            if not best_gem then goto next_jar end

            dothistimeout("get #" .. jar.id .. " from #" .. locker_id, 3, Regex.new("^You remove"))
            local jar_hash = nil
            for _, obj in ipairs(lootsack.contents or {}) do
                if obj.name:gsub("large |medium |small |tiny |some ", "") == best_gem then
                    local result = dothistimeout("_drag #" .. obj.id .. " #" .. jar.id, 3,
                        Regex.new("^You (?:add|put)|is full|does not appear to be a suitable container for"))
                    if result and Regex.test(result, "^You (?:add|put)") then
                        -- Jar is now labelled; read its new name
                        dothistimeout("put #" .. jar.id .. " in #" .. lootsack.id, 3, Regex.new("^You (?:put|tuck|place)"))
                        for _, inv_obj in ipairs(GameObj.inv()) do
                            if inv_obj.id == jar.id then
                                local gem_name = (inv_obj.after_name or ""):gsub("^containing |large |medium |small |tiny |some ", "")
                                dothistimeout("get #" .. jar.id, 3, Regex.new("^You"))
                                jar_hash = { gem = gem_name, count = 1, full = false }
                                jars[#jars + 1] = jar_hash
                                empty_count = empty_count - 1
                                break
                            end
                        end
                    elseif result and Regex.test(result, "is full") then
                        dothistimeout("put #" .. obj.id .. " in #" .. lootsack.id, 3, Regex.new("^You (?:put|tuck|place)"))
                        if jar_hash then jar_hash.full = true end
                        break
                    elseif result and Regex.test(result, "does not appear to be a suitable container for") then
                        not_suitable[obj.id] = true
                        fput("put #" .. obj.id .. " in #" .. lootsack.id)
                    end
                end
            end
            dothistimeout("put #" .. jar.id .. " in #" .. locker_id, 3, Regex.new("^You (?:put|place)"))
        end

        ::next_jar::
    end

    dothistimeout("close locker", 3, Regex.new("^You close|already closed"))
    save_jars(jars)
    save_empty_jar_count(empty_count)
    fill_hands()
end

--- Raid stockpile for bounty gems.
function M.raid_stockpile(settings)
    local task = checkbounty()
    if not task then
        echo("[SLoot] error: no gem bounty active")
        return false
    end
    local gem, count_str = task:match("gem dealer.* requesting (?:a|an|some) (.-)\\..*retrieve (%d+) (?:more )?of them\\.")
    if not gem then
        echo("[SLoot] error: couldn't parse bounty task")
        return false
    end
    local count = tonumber(count_str) or 0
    gem = gem:gsub("large |medium |small |tiny |some ", "")

    local lootsack = sacks_mod.sacks["gem"]
    if not lootsack then return false end

    local locker_id, contents = open_locker_get_contents()
    if not locker_id or not contents then
        dothistimeout("close locker", 3, Regex.new("^You close|already closed"))
        return false
    end

    local jars = load_jars()
    if not jars then
        dothistimeout("close locker", 3, Regex.new("^You close|already closed"))
        return false
    end

    local pat = gem:gsub("y$", "(?:y|ie)"):gsub("z$", "ze?"):gsub("%b ", "s? ")
    local jar_hash = nil
    local locker_jar = nil
    for _, jh in ipairs(jars) do
        if Regex.test(jh.gem, "^" .. pat .. "s?$") and jh.count >= count then
            jar_hash = jh
            for _, obj in ipairs(contents) do
                if obj.after_name then
                    local base = obj.after_name:gsub("^containing |large |medium |small |tiny |some ", "")
                    if Regex.test(base, "^" .. pat .. "s?$") then
                        locker_jar = obj; break
                    end
                end
            end
            break
        end
    end

    if not jar_hash or not locker_jar then
        dothistimeout("close locker", 3, Regex.new("^You close|already closed"))
        return false
    end

    empty_hands()
    dothistimeout("get #" .. locker_jar.id .. " from #" .. locker_id, 3, Regex.new("^You remove"))

    for _ = 1, count do
        dothistimeout("shake #" .. locker_jar.id, 3, Regex.new("^You .*shake"))
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        local gem_obj = (rh and rh.id ~= locker_jar.id and rh) or (lh and lh.id ~= locker_jar.id and lh)
        if gem_obj then
            dothistimeout("put #" .. gem_obj.id .. " in #" .. lootsack.id, 3, Regex.new("^You (?:put|tuck|place)"))
            jar_hash.count = jar_hash.count - 1
            jar_hash.full = false
        end
    end

    dothistimeout("put #" .. locker_jar.id .. " in #" .. locker_id, 3, Regex.new("^You (?:put|place)"))

    if jar_hash.count < 1 then
        -- Remove from list
        local empty_count = load_empty_jar_count()
        for i, jh in ipairs(jars) do
            if jh == jar_hash then table.remove(jars, i); break end
        end
        save_empty_jar_count(empty_count + 1)
    end

    save_jars(jars)
    fill_hands()
    dothistimeout("close locker", 3, Regex.new("^You close|already closed"))
    return true
end

return M
