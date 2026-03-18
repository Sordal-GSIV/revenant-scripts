-- lib/gs/effects.lua
-- GemStone IV effect registries: Spells, Buffs, Debuffs, Cooldowns.
--
-- Mirrors Lich5's Effects::Spells / Effects::Buffs / Effects::Debuffs /
-- Effects::Cooldowns API (Lich5: lib/gemstone/effects.rb + lib/common/xmlparser.rb).
--
-- XML stream format:
--   <dialogData id="Debuffs" clear='t'>   → clear that registry
--   <progressBar id='N' text='Bind' time='0:05:30'>  → store expiry by name + id
--   time='indefinite'  → store expiry = os.time() + DECADE
--
-- Each registry exposes:
--   .active(name_or_id)   → bool (expiry > now)
--   .expiration(name_or_id) → unix timestamp (0 = not present)
--   .time_left(name_or_id)  → seconds remaining (0 if expired/absent)
--   .to_table()           → shallow copy: {name/id → expiry_timestamp, ...}

local DECADE = 10 * 31536000  -- 10 * 365.25 days in seconds (indefinite sentinel)

-- PSM3 dialog IDs recognized by the game
local DIALOG_IDS = { "Buffs", "Active Spells", "Debuffs", "Cooldowns" }
local DIALOG_SET = {}
for _, id in ipairs(DIALOG_IDS) do DIALOG_SET[id] = true end

-- Internal storage: { dialog_id → { [name_or_id] = expiry_unix_ts, ... } }
local _data = {}
for _, id in ipairs(DIALOG_IDS) do _data[id] = {} end

-- Track which dialog we are currently inside (for multi-line XML parsing)
local _current_dialog = nil

-------------------------------------------------------------------------------
-- XML attribute extractor
-- Handles both single and double quoted attribute values.
-------------------------------------------------------------------------------
local function get_attr(text, name)
    return text:match(name .. "=[\"']([^\"']*)[\"']")
end

-------------------------------------------------------------------------------
-- DownstreamHook: parse dialogData and progressBar elements
-------------------------------------------------------------------------------
DownstreamHook.add("__effects_parser", function(line)
    -- <dialogData id="Debuffs"> or <dialogData id='Active Spells' clear='t'>
    local dialog_id = line:match("<dialogData[^>]+id=[\"']([^\"']+)[\"']")
    if dialog_id then
        if DIALOG_SET[dialog_id] then
            _current_dialog = dialog_id
            -- clear='t' means reset the registry for this dialog
            local clear = get_attr(line, "clear")
            if clear == "t" or clear == "true" then
                _data[dialog_id] = {}
            end
        else
            _current_dialog = nil
        end
        return line
    end

    -- </dialogData> closes the active context
    if line:match("</dialogData>") then
        _current_dialog = nil
        return line
    end

    -- <progressBar id='N' text='Effect Name' time='H:MM:SS'>
    if _current_dialog and line:match("<progressBar") then
        local id_str = get_attr(line, "id")
        local text   = get_attr(line, "text")
        local time   = get_attr(line, "time")

        if text and time then
            local expiry
            if time:lower() == "indefinite" then
                expiry = os.time() + DECADE
            else
                local h, m, s = time:match("^(%d+):(%d+):(%d+)$")
                if h then
                    expiry = os.time() + tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
                end
            end

            if expiry then
                local reg = _data[_current_dialog]
                reg[text] = expiry
                if id_str then
                    local id_num = tonumber(id_str)
                    if id_num then reg[id_num] = expiry end
                end
            end
        end
    end

    return line
end)

-------------------------------------------------------------------------------
-- Registry factory
-------------------------------------------------------------------------------
local function make_registry(dialog_id)
    local R = {}

    function R.to_table()
        local copy = {}
        for k, v in pairs(_data[dialog_id]) do copy[k] = v end
        return copy
    end

    function R.expiration(effect)
        local reg = _data[dialog_id]
        -- Regex object: test each string key, return first match (mirrors Lich5 Regexp branch)
        if type(effect) == "userdata" then
            for k, v in pairs(reg) do
                if type(k) == "string" and effect:test(k) then return v end
            end
            return 0
        end
        -- String or number: exact key lookup only (Lich5: to_h.fetch(effect, 0))
        return reg[effect] or 0
    end

    function R.active(effect)
        return R.expiration(effect) > os.time()
    end

    -- Returns minutes remaining, matching Lich5's time_left (which divides by 60).
    -- Returns 0 when effect is not present or has expired.
    function R.time_left(effect)
        local exp = R.expiration(effect)
        if exp == 0 then return 0 end
        local left = (exp - os.time()) / 60.0
        return left > 0 and left or 0
    end

    -- Iterates all entries in the registry: fn(key, expiry_timestamp).
    -- Keys are strings (effect name) or integers (bar id).
    -- Mirrors Lich5's Enumerable#each on Registry.
    function R.each(fn)
        for k, v in pairs(_data[dialog_id]) do
            fn(k, v)
        end
    end

    return R
end

-------------------------------------------------------------------------------
-- Public API — mirroring Lich5: Effects::Spells, ::Buffs, ::Debuffs, ::Cooldowns
-------------------------------------------------------------------------------
local Effects = {
    Spells    = make_registry("Active Spells"),
    Buffs     = make_registry("Buffs"),
    Debuffs   = make_registry("Debuffs"),
    Cooldowns = make_registry("Cooldowns"),
}

return Effects
