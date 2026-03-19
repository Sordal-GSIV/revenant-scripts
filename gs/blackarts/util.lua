--- @module blackarts.util
-- Utility functions. Ported from BlackArts::Util (BlackArts.lic v3.12.x)

local state    = require("state")
local settings_mod = require("settings")

local M = {}

-- Set by init.lua after loading cfg
M.cfg = nil

--------------------------------------------------------------------------------
-- Messaging
--------------------------------------------------------------------------------

function M.msg(msg_type, text)
    if msg_type == "debug" and not (M.cfg and M.cfg.debug) then return end
    if type(text) == "table" then text = Json.encode(text) end
    echo("[BlackArts] " .. tostring(text))
end

function M.msg_error(text)
    M.msg("error", "** " .. tostring(text) .. " **")
end

--------------------------------------------------------------------------------
-- String helpers
--------------------------------------------------------------------------------

function M.title_case(str)
    local minor = { a=1, an=1, the=1, ["and"]=1, but=1, or_=1, ["for"]=1,
                    nor=1, on=1, at=1, to=1, from=1, by=1, of=1 }
    local words = {}
    for w in string.gmatch(str, "%S+") do
        if minor[w:lower()] then
            words[#words + 1] = w
        else
            words[#words + 1] = w:sub(1,1):upper() .. w:sub(2)
        end
    end
    return table.concat(words, " ")
end

function M.add_commas(num)
    local s = tostring(math.floor(num))
    while true do
        local k
        s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

function M.split(str, sep)
    local result = {}
    for part in string.gmatch(str, "([^" .. sep .. "]+)") do
        result[#result + 1] = part:match("^%s*(.-)%s*$")
    end
    return result
end

--------------------------------------------------------------------------------
-- Round-time / timing
--------------------------------------------------------------------------------

function M.wait_rt()
    sleep(0.2)
    waitcastrt()
    waitrt()
    sleep(0.2)
end

--------------------------------------------------------------------------------
-- Day/night check (Elanthia uses different time zones from EST)
-- Returns true during daylight, false at night, nil at dawn/dusk
--------------------------------------------------------------------------------

function M.is_sunlight()
    local server_time = GameState.server_time or os.time()
    local seconds = (server_time - (5 * 60 * 60)) % (60 * 60 * 24)
    local hours   = math.floor(seconds / (60 * 60))
    local minutes = math.floor((seconds % (60 * 60)) / 60)
    if (hours > 6 or (hours == 6 and minutes > 30)) and hours < 18 then
        return true
    elseif hours < 5 or hours > 20 then
        return false
    end
    return nil
end

function M.is_moonlight()
    return not M.is_sunlight()
end

--------------------------------------------------------------------------------
-- Mana / spirit waiting (with optional supplement spells)
--------------------------------------------------------------------------------

function M.check_mana(amount)
    if checkmana() >= amount then return end

    -- Try mana supplements
    if M.cfg then
        if M.cfg.use_wracking and Spell[9918].known and not Spell[9012].active then
            local spirit_needed = 6
            for _, n in ipairs({9912, 9913, 9914, 9916, 9916, 9916}) do
                if Spell[n].active then spirit_needed = spirit_needed + 1 end
            end
            if checkspirit(spirit_needed) then
                Spell[9918]:cast()
            end
        elseif M.cfg.use_sigil_power and Spell[9718].known then
            Spell[9718]:cast()
        elseif Spell[9813] and Spell[9813].known and not Effects.Cooldowns.active("Symbol of Mana") then
            Spell[9813]:cast()
        end
    end

    if checkmana() >= amount then return end
    M.msg("yellow", "Waiting for mana...")
    wait_until(function() return checkmana() >= amount end)
end

function M.check_spirit()
    local needed = 3
    if Spell[9912].active then needed = needed + 1 end
    if Spell[9913].active then needed = needed + 1 end
    if Spell[9914].active then needed = needed + 1 end
    if Spell[9916].active then needed = needed + 3 end

    if checkspirit(needed) then return end

    -- Empaths/Clerics can meditate for faster spirit recovery
    if Char.prof == "Empath" or Char.prof == "Cleric" then
        if not Effects.Spells.active("Meditation") then
            M.msg("yellow", "Meditating for faster spirit recovery...")
            local result = fput("meditate")
            if result and result:find("You kneel down and begin to meditate") or
               (result and result:find("You begin to meditate")) then
                waitfor("You wake from your meditation", "Your action interrupts your meditation")
            end
            while not GameState.standing do
                fput("stand")
                sleep(0.2)
            end
        end
    end

    M.msg("yellow", "Waiting for spirit...")
    while not checkspirit(needed) do
        sleep(0.3)
    end
end

--------------------------------------------------------------------------------
-- Sigil of Concentration refresh
--------------------------------------------------------------------------------

function M.sigil_concentration()
    if not (M.cfg and M.cfg.use_sigil_concentration) then return end
    if not Spell[9714].known then return end
    if checkstamina() < 30 then return end
    if Effects.Spells.time_left("Sigil of Concentration") > 3 then return end
    Spell[9813]:cast()
end

--------------------------------------------------------------------------------
-- Eat manna bread (spell 203) to maintain Manna buff
--------------------------------------------------------------------------------

function M.eat_bread()
    if Effects.Spells.time_left("Manna") > 10 then return end
    if not (Spell[203].known and Spell[203].affordable) then return end

    local inv = require("inventory")
    inv.free_hands({ both = true })
    Spell[203]:cast()
    sleep(0.5)
    waitcastrt()

    local item = GameObj.right_hand() or GameObj.left_hand()
    while item and item.id do
        fput("gobble my " .. (item.noun or "bread"))
        M.wait_rt()
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        if (rh and rh.id == item.id) or (lh and lh.id == item.id) then
            break  -- couldn't eat it
        end
        break
    end
    inv.free_hands({ both = true })
end

--------------------------------------------------------------------------------
-- Cast a spell safely (skips if in no_magic room)
--------------------------------------------------------------------------------

function M.cast_spell(spell_no)
    if M.cfg and M.cfg.no_magic then
        for _, n in ipairs(M.cfg.no_magic) do
            if n == spell_no then return end
        end
    end
    if not (Spell[spell_no] and Spell[spell_no].known and Spell[spell_no].affordable) then return end
    local result = Spell[spell_no]:cast()
    if result and result:find("Your magic fizzles ineffectually") then
        M.msg("info", "Spell fizzled, adding to no-magic room list")
        if M.cfg then
            M.cfg.no_magic[#M.cfg.no_magic + 1] = spell_no
            settings_mod.save(M.cfg)
        end
    end
end

--------------------------------------------------------------------------------
-- Banking helpers
--------------------------------------------------------------------------------

function M.silver_check()
    return checksilvers()
end

function M.silver_deposit(currency)
    if M.cfg and M.cfg.no_bank then return end
    currency = currency or "silver"
    local silver = M.silver_check()
    if silver == 0 and currency == "silver" then return end
    go2("bank")
    fput("deposit " .. currency)
end

function M.silver_withdraw(amount)
    if M.cfg and M.cfg.no_bank then return end
    if M.silver_check() > amount then return end
    M.silver_deposit()
    go2("bank")
    fput("withdraw " .. tostring(amount) .. " silvers")
end

--------------------------------------------------------------------------------
-- Note management
--------------------------------------------------------------------------------

local NOTE_NAMES = {
    "Northwatch bond note", "Icemule promissory note",
    "Borthuum Mining Company scrip", "Wehnimer's promissory note",
    "Torren promissory note", "mining chit", "City-States promissory note",
    "Vornavis promissory note", "Mist Harbor promissory note",
    "salt-stained kraken chit",
}

local function find_note_in_inv()
    for _, item in ipairs(GameObj.inv()) do
        for _, note_name in ipairs(NOTE_NAMES) do
            if item.name and item.name:find(note_name, 1, true) then
                return item
            end
        end
        if item.contents then
            for _, child in ipairs(item.contents) do
                for _, note_name in ipairs(NOTE_NAMES) do
                    if child.name and child.name:find(note_name, 1, true) then
                        return child
                    end
                end
            end
        end
    end
    return nil
end

function M.get_note(force)
    local inv_mod = require("inventory")
    state.note = find_note_in_inv()

    if M.cfg and M.cfg.no_bank then return end

    local need_note = force or false
    if state.note then
        -- Check denomination
        -- If below refresh threshold, we'll get a new one
        need_note = need_note  -- simplified: if we have one, keep it unless forced
    else
        need_note = true
    end

    if not need_note then return end

    go2("bank")
    M.silver_deposit("all")

    local withdrawal = state.note_withdrawal or 50000
    local result = dothistimeout(
        "withdraw " .. tostring(withdrawal) .. " note",
        5,
        Regex.new("The teller carefully records|Very well|The teller hands you|The teller makes|seem to have that much")
    )

    if result and result:find("seem to have that much") then
        M.msg_error("Insufficient funds! Exiting.")
        error("insufficient funds")
    end

    M.wait_rt()
    state.note = find_note_in_inv() or GameObj.right_hand() or GameObj.left_hand()
    if state.note then
        inv_mod.single_drag(state.note)
    end
end

--------------------------------------------------------------------------------
-- Read a shop menu — returns {item_name -> order_string} map
--------------------------------------------------------------------------------

function M.read_menu()
    local menu = {}
    fput("menu")
    for _ = 1, 60 do
        local line = get()
        if not line then break end
        -- Match lines like: "   1.  flask of clear water #1     200 silvers"
        local order_num, name = line:match("^%s*(%d+)%.%s+(.-)%s*#%d")
        if order_num and name then
            menu[name:lower()] = order_num
        end
        if line:find("<prompt") or line:find("^>") then break end
    end
    return menu
end

--------------------------------------------------------------------------------
-- Location: in_town? check
--------------------------------------------------------------------------------

local TOWN_LOCATIONS = {
    "Cysaegir", "Icemule Trace", "Kharam-Dzu", "Mist Harbor",
    "Moonshine Manor", "River's Rest", "Solhaven",
    "Ta'Illistim", "Ta'Vaalor", "Wehnimer's Landing", "Zul Logoth",
    "the town of Icemule Trace", "the town of Kharam-Dzu",
    "the town of River's Rest", "the town of Solhaven",
    "the town of Sylvarraend",
}

function M.in_town(room_id)
    room_id = room_id or Room.id
    if not room_id then return false end
    local rm = Room[room_id]
    if not rm then return false end
    local loc = rm.location or ""
    for _, town in ipairs(TOWN_LOCATIONS) do
        if loc:find(town, 1, true) then return true end
    end
    if Regex.test(loc, "inside the (?:.* town|glacier-locked|elven city|elven fortress)|Guild$") then
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Travel helpers
--------------------------------------------------------------------------------

function M.travel(room_id)
    if not room_id then return end
    M.msg("debug", "Util.travel: room = " .. tostring(room_id))
    if Room.id == tonumber(room_id) then return end
    go2(tostring(room_id))
end

function M.go2(place)
    if GameState.hidden or GameState.invisible then fput("unhide") end
    if place and Room.id == tonumber(place) then return end
    go2(tostring(place))
end

function M.is_workshop()
    local rm = Room[Room.id]
    if not rm then return false end
    if rm.tags then
        for _, tag in ipairs(rm.tags) do
            if tag:find(Char.prof:lower() .. " alchemy workshop") then
                return true
            end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Guild travel: find next unvisited guild in west/east group
--------------------------------------------------------------------------------

function M.find_next_guild()
    local current_town_result = Map.find_nearest_by_tag("town")
    if not current_town_result then
        M.go2(Char.prof:lower() .. " alchemy administrator")
        M.msg("yellow", "Sleeping " .. tostring(M.cfg.guild_pause) .. " seconds before rechecking.")
        sleep(M.cfg.guild_pause)
        return
    end
    local current_town = current_town_result.id

    -- Determine which guild group we're in
    local locations = nil
    for _, id in ipairs(state.west_guilds) do
        if id == current_town then locations = state.west_guilds; break end
    end
    if not locations then
        for _, id in ipairs(state.east_guilds) do
            if id == current_town then locations = state.east_guilds; break end
        end
    end

    if not locations or #locations <= 1 or not (M.cfg and M.cfg.guild_travel) then
        M.go2(Char.prof:lower() .. " alchemy administrator")
        M.msg("yellow", "Sleeping " .. tostring(M.cfg.guild_pause) .. " seconds before rechecking.")
        sleep(M.cfg.guild_pause)
        return
    end

    -- Find nearest unvisited town
    local next_town = nil
    local best_cost = nil
    for _, town_id in ipairs(locations) do
        -- Skip already visited
        local visited = false
        for _, v in ipairs(state.visited_towns) do
            if v == town_id then visited = true; break end
        end
        if not visited then
            local cost = Map.path_cost(Room.id, town_id)
            if cost and (not best_cost or cost < best_cost) then
                best_cost = cost
                next_town = town_id
            end
        end
    end

    if not next_town then
        -- Reset cycle
        state.visited_towns = {state.start_town}
        next_town = state.start_town
        M.go2(Char.prof:lower() .. " alchemy administrator")
        M.msg("yellow", "Sleeping " .. tostring(M.cfg.guild_pause) .. " seconds before moving to next guild.")
        sleep(M.cfg.guild_pause)
    end

    -- Find the administrator in that town
    local guild_result = Map.find_nearest_by_tag(Char.prof:lower() .. " alchemy administrator")
    M.msg("debug", "find_next_guild: next_guild = " .. tostring(guild_result and guild_result.id))

    state.visited_towns[#state.visited_towns + 1] = next_town
    if guild_result then
        M.travel(guild_result.id)
    end
end

--------------------------------------------------------------------------------
-- Find all nearby workshops (within cost 10, excluding known non-workshop rooms)
--------------------------------------------------------------------------------

function M.find_workshops()
    local EXCLUDED = {34600, 34601}
    local results = Map.find_all_nearest_by_tag(Char.prof:lower() .. " alchemy workshop")
    if not results or #results == 0 then
        M.msg_error("Unable to find workshops for " .. Char.prof)
        error("no workshops found")
    end
    local filtered = {}
    for _, r in ipairs(results) do
        local cost = Map.path_cost(Room.id, r.id)
        if cost and cost <= 10 then
            local excluded = false
            for _, ex in ipairs(EXCLUDED) do
                if r.id == ex then excluded = true; break end
            end
            if not excluded then
                filtered[#filtered + 1] = r
            end
        end
    end
    table.sort(filtered, function(a, b)
        local ca = Map.path_cost(Room.id, a.id) or 999
        local cb = Map.path_cost(Room.id, b.id) or 999
        return ca < cb
    end)
    if #filtered == 0 then
        M.msg_error("Unable to find nearby workshops for " .. Char.prof)
        error("no nearby workshops found")
    end
    return filtered
end

--------------------------------------------------------------------------------
-- Forage name normalisation (strip descriptors that block FORAGE command)
--------------------------------------------------------------------------------

local FORAGE_FIXES = {
    ["twisted black mawflower"]      = "mawflower",
    ["small green olive"]            = "green olive",
    ["oozing fleshsore bulb"]        = "fleshsore bulb",
    ["rotting bile green fleshbulb"] = "fleshbulb",
    ["discolored fleshbinder bud"]   = "fleshbinder bud",
    ["slime-covered grave blossom"]  = "grave blossom",
    ["fragrant white lily"]          = "white lily",
    ["trollfear mushroom"]           = "mushroom",
    ["vermilion fire lily"]          = "fire lily",
    ["orange tiger lily"]            = "tiger lily",
    ["golden flaeshorn berry"]       = "flaeshorn berry",
    ["white alligator lily"]         = "alligator lily",
    ["dark pink rain lily"]          = "pink rain lily",
    ["white spider lily"]            = "spider lily",
    ["large black toadstool"]        = "black toadstool",
    ["glowing green lichen"]         = "green lichen",
    ["luminescent green fungus"]     = "green fungus",
    ["black-tipped wyrm thorn"]      = "wyrm thorn",
    ["fetid black slime"]            = "black slime",
    ["gnarled pandanus twig"]        = "pandanus twig",
    ["giant glowing toadstool"]      = "glowing toadstool",
    ["waxy banana leaf"]             = "banana leaf",
}

function M.fix_forage_name(name)
    if FORAGE_FIXES[name] then return FORAGE_FIXES[name] end
    local stripped = name:match("%w+ of (.+)$")
    if stripped then return stripped end
    if name:find("iceblossom") then return "iceblossom" end
    if name:find("stick") then return "stick" end
    if name:find("mold") then return "mold" end
    return name
end

--------------------------------------------------------------------------------
-- Mapped room helper (ensures Room.id is populated before operations)
--------------------------------------------------------------------------------

function M.mapped_room()
    -- In Revenant, Room.id is always current. No-op placeholder.
end

--------------------------------------------------------------------------------
-- Jar count helper — reads "measure #id" to count doses in a jar/flask
--------------------------------------------------------------------------------

function M.jar_count(jar)
    if not jar or not jar.id then return 0 end
    local lines = {}
    fput(string.format("measure #%s", jar.id))
    for _ = 1, 10 do
        local line = get()
        if not line then break end
        lines[#lines + 1] = line
        if line:find("<prompt") or line:find("^>") then break end
    end
    for _, line in ipairs(lines) do
        local n = line:match("count a total of (%d+)")
        if n then return tonumber(n) end
        local n2 = line:match("(%d+) dose")
        if n2 then return tonumber(n2) end
    end
    return 1
end

--------------------------------------------------------------------------------
-- Sell an item at consignment store
--------------------------------------------------------------------------------

function M.sell_item(item)
    if not item or not item.id then return end
    local inv_mod = require("inventory")
    inv_mod.drag(item)
    fput(string.format("sell #%s", item.id))
    M.wait_rt()
end

--------------------------------------------------------------------------------
-- get_lines helper: issue a command and collect lines until regex matches
--------------------------------------------------------------------------------

function M.get_lines(cmd, stop_rx)
    fput(cmd)
    local lines = {}
    for _ = 1, 60 do
        local line = get()
        if not line then break end
        lines[#lines + 1] = line
        if Regex.test(line, stop_rx) then break end
        if line:find("<prompt") or line:match("^>$") then break end
    end
    return lines
end

--------------------------------------------------------------------------------
-- get_res helper: issue a command, return the first matching line
--------------------------------------------------------------------------------

function M.get_res(cmd, match_rx)
    fput(cmd)
    for _ = 1, 30 do
        local line = get()
        if not line then break end
        if Regex.test(line, match_rx) then return line end
        if line:find("<prompt") or line:match("^>$") then break end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Find trash can in current room (meta:trashcan tag or common nouns)
--------------------------------------------------------------------------------

function M.find_trash()
    local rm = Room[Room.id]
    if rm and rm.tags then
        for _, tag in ipairs(rm.tags) do
            local can = tag:match("meta:trashcan:(.*)")
            if can then
                for _, obj in ipairs(GameObj.loot()) do
                    if obj.name and obj.name:find(can, 1, true) then
                        return obj
                    end
                end
            end
        end
    end
    local can_nouns = {"barrel", "bin", "basket", "bucket", "canister", "case",
                       "casket", "crate", "hearth", "pit", "stump", "urn",
                       "wastebasket", "wastebin", "wastecan"}
    for _, obj in ipairs(GameObj.loot()) do
        for _, noun in ipairs(can_nouns) do
            if obj.noun == noun then
                local lines = M.get_lines("look in #" .. obj.id, "variety of garbage|I could not find")
                for _, line in ipairs(lines) do
                    if line:find("variety of garbage") then return obj end
                end
            end
        end
    end
    return nil
end

return M
