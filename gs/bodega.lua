--- @revenant-script
--- name: bodega
--- version: 0.6.0
--- author: Ondreian
--- game: gs
--- tags: playershops
--- description: Player shop directory scanner — parses shop directories and generates JSON
---
--- Original Lich5 authors: Ondreian
--- Ported to Revenant Lua from bodega.lic v0.6
--- @lic-certified: complete 2026-03-19
---
--- Usage: ;bodega --help
---
--- Features:
---   - Scans player shop directories across all towns via shop commands
---   - Full item property extraction (enchant, weight, material, worn, enhancives, gemstones)
---   - Smart scan mode (--smart) for incremental updates with diff logic
---   - Removed/added item tracking with safeguards
---   - JSON output with per-town files
---   - API-based upload to remote services
---   - Search index with CDN sync
---   - Exposes Bodega module for other scripts
---
--- changelog:
---   v0.6 - Fix shop ID swap handling during maintenance reboots
---          - Smart scan now automatically syncs room_title with preamble
---          - Prevents stale room metadata when shop IDs are reassigned
---          - Maintains shop type detection during synchronization
---   v0.5 - Add smart parsing mode for 90%+ performance improvement
---          - New --smart flag for intelligent item inspection
---          - Loads existing JSON, compares IDs, only inspects new items
---          - Automatic removal of deleted items from cache
---          - Comprehensive efficiency reporting and change detection
---   v0.4 - Add API-based upload
---   v0.3 - Update for compatibility
---   v0.2 - Update for compatibility

local VERSION = "0.6.0"

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function is_integer(s)
    return type(s) == "string" and s:match("^[+-]?%d+$") ~= nil
end

local function trim(s)
    if not s then return "" end
    return s:match("^%s*(.-)%s*$")
end

local function safe_string(t)
    local s = tostring(t):lower()
    s = s:gsub("ta'", "ta_")
    s = s:gsub("'", ""):gsub(",", "")
    s = s:gsub("%-", "_"):gsub("%s", "_")
    return s
end

local function fmt_time(diff)
    if diff < 1 then
        return tostring(math.floor(diff * 1000)) .. "ms"
    end
    local total = math.floor(diff)
    local s = total % 60
    local m = math.floor(total / 60) % 60
    local h = math.floor(total / 3600) % 24
    local d = math.floor(total / 86400)
    local parts = {}
    if d > 0 then parts[#parts + 1] = string.format("%02dd", d) end
    if h > 0 then parts[#parts + 1] = string.format("%02dh", h) end
    if m > 0 then parts[#parts + 1] = string.format("%02dm", m) end
    if s > 0 then parts[#parts + 1] = string.format("%02ds", s) end
    if #parts == 0 then return "0s" end
    return table.concat(parts, " ")
end

local function parse_iso_time(str)
    if not str then return nil end
    local y, mo, dy, h, mi, sc = str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    if y then
        return os.time({
            year = tonumber(y), month = tonumber(mo), day = tonumber(dy),
            hour = tonumber(h), min = tonumber(mi), sec = tonumber(sc),
        })
    end
    return nil
end

local function iso_now()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function set_diff(a, b)
    local result = {}
    for k in pairs(a) do
        if not b[k] then result[k] = true end
    end
    return result
end

local function set_intersect(a, b)
    local result = {}
    for k in pairs(a) do
        if b[k] then result[k] = true end
    end
    return result
end

local function set_size(s)
    local n = 0
    for _ in pairs(s) do n = n + 1 end
    return n
end

local function split(str, sep)
    local result = {}
    for part in str:gmatch("[^" .. sep .. "]+") do
        result[#result + 1] = trim(part)
    end
    return result
end

local function split_multi_space(str)
    local result = {}
    local pos = 1
    while pos <= #str do
        local s, e = str:find("%s%s+", pos)
        if s then
            local chunk = trim(str:sub(pos, s - 1))
            if chunk ~= "" then result[#result + 1] = chunk end
            pos = e + 1
        else
            local chunk = trim(str:sub(pos))
            if chunk ~= "" then result[#result + 1] = chunk end
            break
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- Bodega Module
--------------------------------------------------------------------------------

local Bodega = {}

--------------------------------------------------------------------------------
-- Log
--------------------------------------------------------------------------------

Bodega.Log = {}

function Bodega.Log.out(msg, label)
    label = label or "debug"
    if type(msg) ~= "string" then msg = tostring(msg) end
    local prefix = "[" .. (Script.name or "bodega") .. "." .. tostring(label) .. "]"
    local safe = msg
    if safe:find("<") and safe:find(">") then
        safe = safe:gsub("<", "("):gsub(">", ")")
    end
    respond('<preset id="debug">' .. prefix .. " " .. safe .. "</preset>")
end

function Bodega.Log.pp(msg, label)
    Bodega.Log.out(msg, label or "debug")
end

function Bodega.Log.dump(...)
    for _, v in ipairs({ ... }) do
        Bodega.Log.pp(v)
    end
end

local Log = Bodega.Log

--------------------------------------------------------------------------------
-- Opts
--------------------------------------------------------------------------------

Bodega.Opts = {}

local _opts_cache = nil

function Bodega.Opts.parse()
    local opts = {}
    local i = 1
    while Script.vars[i] do
        local arg = Script.vars[i]
        if arg:sub(1, 2) == "--" then
            local rest = arg:sub(3)
            local name, val = rest:match("^([^=]+)=(.+)$")
            if name then
                local parts = {}
                for part in val:gmatch("[^,]+") do
                    parts[#parts + 1] = part
                end
                opts[name] = #parts == 1 and parts[1] or parts
            else
                opts[rest] = true
            end
        else
            if arg == "smart" then
                opts.smart = true
            else
                opts[arg] = true
            end
        end
        i = i + 1
    end
    return opts
end

local function get_opts()
    if not _opts_cache then
        _opts_cache = Bodega.Opts.parse()
    end
    return _opts_cache
end

function Bodega.Opts.get(key, default)
    local val = get_opts()[key]
    if val == nil then return default end
    return val
end

function Bodega.Opts.has(key)
    return get_opts()[key] ~= nil
end

function Bodega.Opts.to_table()
    return get_opts()
end

local Opts = Bodega.Opts

--------------------------------------------------------------------------------
-- Messages (patterns for parsing game output)
--------------------------------------------------------------------------------

Bodega.Messages = {
    TOWNS    = "Valid options include:%s*(.-)%.",
    COMMAND  = "You can use the (.-) command to browse",
    NEW_ROOM = "^(.+)%s%((%w+)%)$",
    SIGN     = "^Written on",
    ITEM     = "^%s*(%d+)%).+for%s+([%d,]+)%s+silver",
}

local Messages = Bodega.Messages

--------------------------------------------------------------------------------
-- Collector: send command, collect lines between start/close patterns w/ retry
--------------------------------------------------------------------------------

local function compare(line, pattern)
    if type(pattern) == "string" then
        return line:find(pattern, 1, true) ~= nil
    end
    return false
end

local function collect(command, start_pat, close_pat, seconds, max_tries)
    seconds = seconds or 5
    max_tries = max_tries or tonumber(Opts.get("max-tries", 3))

    for attempt = 0, max_tries - 1 do
        if attempt > 0 then
            Log.out(command, "retry")
        end
        fput(command)
        local result = {}
        local deadline = os.time() + seconds
        while os.time() < deadline do
            local line = nget()
            if not line then
                pause(0.1)
            else
                if compare(line, start_pat) or #result > 0 then
                    result[#result + 1] = line
                end
                if compare(line, close_pat) and #result > 0 then
                    return result
                end
            end
        end
    end
    error("Collector(start: " .. tostring(start_pat) .. ", close: " .. tostring(close_pat) ..
        ") failed to complete in " .. seconds .. " seconds")
end

--------------------------------------------------------------------------------
-- Extractor: extract item properties from inspection text
--------------------------------------------------------------------------------

Bodega.Extractor = {}

-- Blacklist: lines to silently ignore
local BLACKLIST_PATTERNS = {
    "^There is nothing there to read%.$",
    "^You carefully inspect",
    "^You get no sense of whether or not .+ may be further lightened%.",
    "there is no recorded information on that item",
    "^You determine that you could not wear the shard%.",
    "^You see nothing unusual%.$",
    "^It imparts no bonus more than usual%.$",
    "^It is difficult to see the .+ clearly from this distance%.",
}

local function is_blacklisted(line)
    for _, pat in ipairs(BLACKLIST_PATTERNS) do
        if line:match(pat) then return true end
    end
    return false
end

-- Enhancive patterns (Regex for named capture groups)
local RE_BOOST     = Regex.new("^It provides a boost of (\\d+) to (.*?)\\.")
local RE_LEVEL_REQ = Regex.new("^This enhancement may not be used by adventurers who have not trained (\\d+) times")

-- Boolean tag patterns
local BOOL_PATTERNS = {
    { tag = "max_deep",     test = function(l) return l:find("pockets could not possibly get any deeper") end },
    { tag = "max_light",    test = function(l) return l:find("is as light as it can get") end },
    { tag = "purpose",      test = function(l) return l:find("appears to serve some purpose") end },
    { tag = "deepenable",   test = function(l) return l:find("you might be able to have a talented merchant deepen its pockets") end },
    { tag = "lightenable",  test = function(l) return l:find("You might be able to have a talented merchant lighten") end },
    { tag = "persists",     test = function(l)
        return l:find("It will persist after its last charge is depleted")
            or l:find("It will persist after its last enhancive charge")
    end },
    { tag = "crumbly",      test = function(l)
        return l:find("but crumble after its last enhancive charge is depleted")
            or l:find("It will crumble into dust after its last charge is depleted")
            or l:find("It will disintegrate after its last charge is depleted")
    end },
    { tag = "small",        test = function(l) return l:find("It is a small item, under a pound") end },
    { tag = "imbeddable",   test = function(l) return l:find("It is a magical item which could be imbedded with a spell") end },
    { tag = "not_wearable", test = function(l) return l:find("You determine that you could not wear") end },
    { tag = "holy",         test = function(l) return l:find("It is a holy item") end },
    { tag = "is_gemstone",  test = function(l) return l:find("The jewel appears to be a powerful relic") end },
}

-- Property extraction patterns (Regex for complex patterns)
local RE_SKILL     = Regex.new("requires skill in (.*?) to use effectively\\.")
local RE_ENCHANT   = Regex.new("^It imparts a bonus of \\+(\\d+) more than usual\\.")
local RE_WEIGHT    = Regex.new("^It appears to weigh about (\\d+) pounds")
local RE_MATERIAL  = Regex.new("^It looks like this item has been mainly crafted out of (.*?)\\.")
local RE_COST      = Regex.new("will cost (\\d+) coins\\.$")
local RE_WORN      = Regex.new("The .+? can be worn(?:, slinging it across the |, hanging it from the |, attaching it to the | around the | in the | on the | over(?: the)? )([^.]+)")
local RE_ACTIVATOR = Regex.new("^It could be activated by (\\w+) it\\.$")
local RE_SPELL     = Regex.new("^It is currently imbedded with the (.*?) spell")
local RE_CHARGES   = Regex.new("(?:looks to have|It has) (.*?) charges remaining")
local RE_SHIELD    = Regex.new("allows you to conclude that it is a (\\w+) shield that")
local RE_ARMOR     = Regex.new(" allows you to conclude that it is (.*?)\\.")
local RE_FLARE     = Regex.new("It has been infused with (.*?)\\.$")
local RE_GEM_BOUND = Regex.new("jewel is bound to (\\w+),")

-- Special worn location overrides (checked before general regex)
local WORN_OVERRIDES = {
    { pattern = "anywhere on the body",                       value = "pin" },
    { pattern = "around the chest, beneath another garment",  value = "undershirt" },
    { pattern = "on the feet, beneath shoes or boots",        value = "socks" },
    { pattern = "slinging it across the shoulders and back",  value = "shoulders" },
    { pattern = "hanging it from the shoulders",              value = "cloak" },
    { pattern = "on the legs",                                value = "pants" },
    { pattern = "around the legs",                            value = "legs" },
}

function Bodega.Extractor.extract(details)
    local props = { raw = {}, tags = {} }

    for idx, line in ipairs(details) do
        local is_gem = Bodega.Extractor._gemstone_property(props, details, idx)
        if not is_gem then
            local got_prop = Bodega.Extractor._props(props, line)
            local got_bool = Bodega.Extractor._bools(props, line)
            local got_enh  = Bodega.Extractor._enhancive(props, trim(line))
            if not is_blacklisted(line) and not got_prop and not got_bool and not got_enh then
                props.raw[#props.raw + 1] = line
            end
        end
    end

    return props
end

function Bodega.Extractor._bools(props, line)
    local found = false
    for _, bp in ipairs(BOOL_PATTERNS) do
        if bp.test(line) then
            props.tags[#props.tags + 1] = bp.tag
            found = true
        end
    end
    return found
end

function Bodega.Extractor._enhancive(props, line)
    local caps = RE_BOOST:captures(line)
    if caps then
        if not props.enhancives then props.enhancives = {} end
        local entry = { boost = tonumber(caps[1]), ability = caps[2] }
        props.enhancives[#props.enhancives + 1] = entry
        return true
    end

    local lcaps = RE_LEVEL_REQ:captures(line)
    if lcaps and props.enhancives and #props.enhancives > 0 then
        props.enhancives[#props.enhancives].level = tonumber(lcaps[1])
        return true
    end

    return false
end

function Bodega.Extractor._gemstone_property(props, lines, index)
    local line = lines[index]
    local prop_match = line:match("^Property:%s+(.+)$")
    if not prop_match then return false end

    local property = { name = trim(prop_match) }

    if lines[index + 1] then
        local rarity = lines[index + 1]:match("^Rarity:%s+(.+)$")
        if rarity then property.rarity = trim(rarity) end
    end

    if lines[index + 2] then
        local mnemonic = lines[index + 2]:match("^Mnemonic:%s+(.+)$")
        if mnemonic then property.mnemonic = trim(mnemonic) end
    end

    if lines[index + 3] then
        local desc = lines[index + 3]:match("^Description:%s+(.+)$")
        if desc then
            local description = trim(desc)
            local ci = index + 4
            while ci <= #lines do
                if lines[ci]:match("^Property:") or lines[ci]:match("^%*")
                    or lines[ci]:match("^You note") or lines[ci]:match("^The jewel") then
                    break
                end
                if trim(lines[ci]) ~= "" then
                    description = description .. " " .. trim(lines[ci])
                end
                ci = ci + 1
            end
            property.description = description
        end
    end

    if lines[index + 4] and lines[index + 4]:match("^%s*%*%s+Activated") then
        property.activated = true
    elseif lines[index + 5] and lines[index + 5]:match("^%s*%*%s+Activated") then
        property.activated = true
    end

    if not props.gemstone_properties then props.gemstone_properties = {} end
    props.gemstone_properties[#props.gemstone_properties + 1] = property
    return true
end

function Bodega.Extractor._props(props, line)
    local found = false

    -- Special worn location overrides first
    for _, override in ipairs(WORN_OVERRIDES) do
        if line:lower():find(override.pattern:lower(), 1, true) then
            props.worn = override.value
            return true
        end
    end

    -- General worn regex
    local worn_cap = RE_WORN:captures(line)
    if worn_cap then props.worn = trim(worn_cap[1]); found = true end

    -- Skill requirement
    local skill_cap = RE_SKILL:captures(line)
    if skill_cap then props.skill = skill_cap[1]; found = true end

    -- Enchantment bonus
    local enchant_cap = RE_ENCHANT:captures(line)
    if enchant_cap then props.enchant = tonumber(enchant_cap[1]); found = true end

    -- Weight
    local weight_cap = RE_WEIGHT:captures(line)
    if weight_cap then props.weight = tonumber(weight_cap[1]); found = true end

    -- Material
    local material_cap = RE_MATERIAL:captures(line)
    if material_cap then props.material = material_cap[1]; found = true end

    -- Cost (from inspect output)
    local cost_cap = RE_COST:captures(line)
    if cost_cap then props.cost = tonumber(cost_cap[1]); found = true end

    -- Activator
    local act_cap = RE_ACTIVATOR:captures(line)
    if act_cap then props.activator = act_cap[1]; found = true end

    -- Imbedded spell
    local spell_cap = RE_SPELL:captures(line)
    if spell_cap then props.spell = spell_cap[1]; found = true end

    -- Charges remaining
    local charges_cap = RE_CHARGES:captures(line)
    if charges_cap then props.charges = charges_cap[1]; found = true end

    -- Shield size
    local shield_cap = RE_SHIELD:captures(line)
    if shield_cap then props.shield_size = shield_cap[1]; found = true end

    -- Armor type
    local armor_cap = RE_ARMOR:captures(line)
    if armor_cap then props.armor_type = armor_cap[1]; found = true end

    -- Flare
    local flare_cap = RE_FLARE:captures(line)
    if flare_cap then props.flare = flare_cap[1]; found = true end

    -- Gemstone binding
    local gem_cap = RE_GEM_BOUND:captures(line)
    if gem_cap then props.gemstone_bound_to = gem_cap[1]; found = true end

    return found
end

--------------------------------------------------------------------------------
-- Assets: local/remote file management
--------------------------------------------------------------------------------

Bodega.Assets = {}

local BODEGA_DIR = "data/bodega"
local REMOTE_URL = "https://bodega.surge.sh"

function Bodega.Assets.init()
    BODEGA_DIR = Opts.get("out", Opts.get("local-dir", "data/bodega"))
    REMOTE_URL = Opts.get("remote", "https://bodega.surge.sh")
    if not File.exists("data") then
        File.mkdir("data")
    end
    if not File.exists(BODEGA_DIR) then
        File.mkdir(BODEGA_DIR)
    end
end

function Bodega.Assets.local_path(filename)
    return BODEGA_DIR .. "/" .. filename
end

function Bodega.Assets.remote_path(filename)
    return REMOTE_URL .. "/" .. filename
end

function Bodega.Assets.checksum(filename)
    local path = Bodega.Assets.local_path(filename)
    if File.exists(path) then
        return Crypto.sha256_file(path)
    end
    return nil
end

function Bodega.Assets.cached_files()
    if not File.exists(BODEGA_DIR) then return {} end
    local all = File.list(BODEGA_DIR)
    local result = {}
    for _, f in ipairs(all) do
        if f:match("%.json$") and not f:match("manifest%.json$") then
            result[#result + 1] = f
        end
    end
    return result
end

function Bodega.Assets.read_local_json(filename)
    local path = Bodega.Assets.local_path(filename)
    if not File.exists(path) then return nil end
    local content = File.read(path)
    if not content or content == "" then return nil end
    local ok, data = pcall(Json.decode, content)
    if ok then return data end
    return nil
end

function Bodega.Assets.write_local_json(data, name)
    local path = Bodega.Assets.local_path(name .. ".json")
    local content = type(data) == "string" and data or Json.encode(data)
    Log.out("... writing " .. path, "filesystem")
    File.write(path, content)
end

function Bodega.Assets.get_remote(filename)
    local url = Bodega.Assets.remote_path(filename)
    local resp = Http.get(url)
    if resp and resp.status == 200 then
        return resp.body
    end
    return nil
end

function Bodega.Assets.is_stale(remote)
    local local_cs = Bodega.Assets.checksum(remote.base_name)
    return local_cs ~= remote.checksum
end

function Bodega.Assets.stream_download(remote)
    local url = remote.url
    local path = Bodega.Assets.local_path(remote.base_name)
    Log.out(string.format("%10s ... %20s >> %s",
        "updating", remote.base_name:gsub("%.json", ""), tostring(remote.size)), "download")
    local resp = Http.get(url)
    if resp and resp.status == 200 then
        File.write(path, resp.body)
    end
end

local Assets = Bodega.Assets

--------------------------------------------------------------------------------
-- Utils
--------------------------------------------------------------------------------

Bodega.Utils = {}

function Bodega.Utils.parse_json(str)
    if not str or str == "" then return {} end
    local ok, data = pcall(Json.decode, str)
    if ok then return data end
    return {}
end

function Bodega.Utils.read_json(filepath)
    local content = File.read(filepath)
    if not content then return {} end
    return Bodega.Utils.parse_json(content)
end

function Bodega.Utils.write_json(data, filepath)
    Log.out("... writing " .. filepath, "filesystem")
    File.write(filepath, type(data) == "string" and data or Json.encode(data))
end

function Bodega.Utils.benchmark(label, template, func)
    label = label or "benchmark"
    template = template or "{{run_time}}"
    local start = os.time()
    local result = func()
    local elapsed = os.time() - start
    local run_time = fmt_time(elapsed)
    Log.out(template:gsub("{{run_time}}", run_time), label)
    return result, run_time
end

function Bodega.Utils.pp(o)
    if type(o) == "table" then
        respond(Json.encode(o))
    else
        respond(tostring(o))
    end
end

local Utils = Bodega.Utils

--------------------------------------------------------------------------------
-- Parser: the main shop scanning engine
--------------------------------------------------------------------------------

Bodega.Parser = {}

-- Module-level state for smart scanning
local smart_stats = nil
local removed_items_data = nil
local added_items_data = nil

function Bodega.Parser.fetch_towns()
    local result = dothistimeout("shop direc", 5, "Valid options include:")
    if result and result:find("Valid options include:") then
        local towns_str = result:match("Valid options include:%s*(.-)%.")
        if towns_str then
            towns_str = towns_str:gsub(" and ", ", ")
            local towns = split(towns_str, ",")
            for i, t in ipairs(towns) do towns[i] = trim(t) end
            return towns
        end
    end
    error("unknown outcome for parsing available towns")
end

local _towns_cache = nil
function Bodega.Parser.towns()
    if not _towns_cache then
        _towns_cache = Bodega.Parser.fetch_towns()
    end
    return _towns_cache
end

function Bodega.Parser.shops(town)
    local result = collect(
        "shop direc " .. town,
        "~*~",
        "You can use the SHOP",
        5
    )

    -- Extract browse command template from last line
    local last_line = result[#result]
    local next_command = last_line:match("You can use the (.-) command to browse")
    if not next_command then
        next_command = "SHOP BROWSE {SHOP#}"
    end

    -- Parse shop entries from middle lines (skip header and footer)
    local by_shop_number = {}
    for i = 2, #result - 1 do
        local row = trim(result[i])
        if row ~= "" then
            local cols = split_multi_space(row)
            for _, col in ipairs(cols) do
                local num, name = col:match("^(%d+)%)%s+(.+)$")
                if num then
                    by_shop_number[#by_shop_number + 1] = { id = num, name = name }
                end
            end
        end
    end

    -- Filter by --shop option
    local shop_filter = Opts.get("shop")
    if shop_filter then
        local filtered = {}
        for _, entry in ipairs(by_shop_number) do
            if entry.name:lower():find(shop_filter:lower(), 1, true) then
                filtered[#filtered + 1] = entry
            end
        end
        by_shop_number = filtered
    end

    return Bodega.Parser.scan_shops(town, by_shop_number, next_command)
end

function Bodega.Parser.scan_shops(town, shops, cmd_template)
    local max_shop_depth = tonumber(Opts.get("max-shop-depth", 10000))
    local results = {}

    for idx, shop in ipairs(shops) do
        if idx > max_shop_depth then break end
        Log.out(string.format("%30s ... Shop(id: %s, name: %s)",
            string.format("scanning [%d/%d]", idx, math.min(#shops, max_shop_depth)),
            shop.id, shop.name), safe_string(town))

        local ok, result = pcall(function()
            local cmd = cmd_template:gsub("{SHOP#}", shop.id)
            if Opts.has("smart") then
                return Bodega.Parser.smart_scan_inv(town, shop.id, shop.name, cmd)
            else
                return Bodega.Parser.scan_inv(town, shop.id, shop.name, cmd)
            end
        end)

        if ok and result then
            results[#results + 1] = result
        elseif not ok then
            Log.out(tostring(result), "error")
        end
    end

    return results
end

function Bodega.Parser.scan_inv(town, id, _name, cmd)
    local result = collect(cmd, "is located in", "You can use the SHOP INSPECT", 5)
    if not result or #result == 0 then return nil end

    local preamble = result[1]
    local inv_lines = {}
    for i = 2, #result do
        inv_lines[#inv_lines + 1] = trim(result[i])
    end

    return {
        preamble = preamble,
        town = town,
        id = id,
        inv = Bodega.Parser.parse_inv(inv_lines),
    }
end

function Bodega.Parser.add_room(acc, row)
    local room_title, branch = row:match(Messages.NEW_ROOM)
    if room_title and branch then
        acc[#acc + 1] = {
            room_title = trim(room_title),
            branch = branch,
            items = {},
        }
    end
end

function Bodega.Parser.add_sign(acc, row)
    if #acc == 0 then return end
    local last = acc[#acc]
    if not last.sign then last.sign = {} end
    last.sign[#last.sign + 1] = row
end

function Bodega.Parser.add_item(acc, row)
    if #acc == 0 then return end
    local item_id, price = row:match("^%s*(%d+)%).+for%s+([%d,]+)%s+silver")
    if item_id then
        local last = acc[#acc]
        last.items[#last.items + 1] = {
            id = item_id,
            browse_price = tonumber(price:gsub(",", "")),
        }
    end
end

function Bodega.Parser.parse_inv(inv)
    local acc = {}

    for _, row in ipairs(inv) do
        if row:find("SHOP INSPECT", 1, true) then break end
        if row:match(Messages.NEW_ROOM) then
            Bodega.Parser.add_room(acc, row)
        end
        if #acc > 0 then
            if row:match(Messages.SIGN) or acc[#acc].sign then
                Bodega.Parser.add_sign(acc, row)
            end
            if row:match("^%s*%d+%)") and not acc[#acc].sign then
                Bodega.Parser.add_item(acc, row)
            end
        end
    end

    -- Inspect each item
    local max_item_depth = tonumber(Opts.get("max-item-depth", 100))
    for _, room in ipairs(acc) do
        local inspected = {}
        for i, item_data in ipairs(room.items) do
            if i > max_item_depth then break end
            inspected[#inspected + 1] = Bodega.Parser.scan_item(item_data.id, item_data.browse_price)
        end
        room.items = inspected
    end

    return acc
end

function Bodega.Parser.get_browse_ids(inv)
    local item_prices = {}
    local acc = {}

    for _, row in ipairs(inv) do
        if row:find("SHOP INSPECT", 1, true) then break end
        if row:match(Messages.NEW_ROOM) then
            Bodega.Parser.add_room(acc, row)
        end
        if #acc > 0 then
            if row:match(Messages.SIGN) or acc[#acc].sign then
                Bodega.Parser.add_sign(acc, row)
            end
            if row:match("^%s*%d+%)") and not acc[#acc].sign then
                local item_id, price = row:match("^%s*(%d+)%).+for%s+([%d,]+)%s+silver")
                if item_id then
                    item_prices[item_id] = tonumber(price:gsub(",", ""))
                end
            end
        end
    end

    return item_prices
end

function Bodega.Parser.load_and_validate_town_json(town)
    local filename = safe_string(town) .. ".json"
    local path = Assets.local_path(filename)
    if not File.exists(path) then return nil end

    local ok, data = pcall(function()
        return Json.decode(File.read(path))
    end)

    if not ok or not data then
        Log.out("Invalid JSON for " .. town .. ", falling back to full parsing", "smart")
        return nil
    end

    if type(data) ~= "table" or type(data.shops) ~= "table" then
        Log.out("Invalid JSON structure for " .. town .. ", falling back to full parsing", "smart")
        return nil
    end

    for _, shop in ipairs(data.shops) do
        if type(shop) ~= "table" or not shop.id or type(shop.inv) ~= "table" then
            Log.out("Invalid shop structure in " .. town .. ", falling back to full parsing", "smart")
            return nil
        end
    end

    Log.out("Loaded existing data for " .. town .. " (" .. #data.shops .. " shops)", "smart")
    return data
end

function Bodega.Parser.find_shop_by_id(town_data, shop_id)
    if not town_data or not town_data.shops then return nil end
    for _, shop in ipairs(town_data.shops) do
        if tostring(shop.id) == tostring(shop_id) then
            Log.out("Found existing shop " .. shop_id .. " in cached data", "smart")
            return shop
        end
    end
    Log.out("Shop " .. shop_id .. " not found in cached data (new shop)", "smart")
    return nil
end

function Bodega.Parser.extract_item_ids_from_shop(shop_data)
    local ids = {}
    if not shop_data or not shop_data.inv then return ids end
    for _, room in ipairs(shop_data.inv) do
        if room.items then
            for _, item in ipairs(room.items) do
                if item.id then ids[tostring(item.id)] = true end
            end
        end
    end
    return ids
end

function Bodega.Parser.smart_scan_inv(town, shop_id, name, cmd)
    Log.out("Smart scanning shop " .. shop_id, "smart")

    if not smart_stats then
        smart_stats = { new_items = 0, removed_items = 0, unchanged_items = 0, shops_scanned = 0 }
    end

    if smart_stats.shops_scanned == 0 then
        Bodega.Parser.load_added_items()
    end

    -- Step 1: Browse shop to get current item IDs
    local result = collect(cmd, "is located in", "You can use the SHOP INSPECT", 5)
    if not result or #result == 0 then return nil end

    local preamble = result[1]
    local inv_lines = {}
    for i = 2, #result do
        inv_lines[#inv_lines + 1] = trim(result[i])
    end

    local current_items = Bodega.Parser.get_browse_ids(inv_lines)
    local current_ids = {}
    for k in pairs(current_items) do current_ids[k] = true end

    Log.out("Found " .. set_size(current_ids) .. " items currently in shop " .. shop_id, "smart")

    -- Step 2: Load existing town data
    local town_data = Bodega.Parser.load_and_validate_town_json(town)

    -- Step 3: Find existing shop
    local existing_shop = Bodega.Parser.find_shop_by_id(town_data, shop_id)

    if not existing_shop then
        Log.out("No existing data for shop " .. shop_id .. ", performing full scan", "smart")
        smart_stats.shops_scanned = smart_stats.shops_scanned + 1
        smart_stats.new_items = smart_stats.new_items + set_size(current_ids)
        return {
            preamble = preamble,
            town = town,
            id = shop_id,
            inv = Bodega.Parser.parse_inv(inv_lines),
        }
    end

    -- Step 4: Extract existing item IDs
    local existing_ids = Bodega.Parser.extract_item_ids_from_shop(existing_shop)
    Log.out("Found " .. set_size(existing_ids) .. " items in cached shop " .. shop_id, "smart")

    -- Step 5: Calculate differences
    local new_ids = set_diff(current_ids, existing_ids)
    local removed_ids_set = set_diff(existing_ids, current_ids)
    local unchanged_ids = set_intersect(current_ids, existing_ids)

    Log.out(string.format("Smart diff for shop %s: %d new, %d removed, %d unchanged",
        shop_id, set_size(new_ids), set_size(removed_ids_set), set_size(unchanged_ids)), "smart")

    smart_stats.new_items = smart_stats.new_items + set_size(new_ids)
    smart_stats.removed_items = smart_stats.removed_items + set_size(removed_ids_set)
    smart_stats.unchanged_items = smart_stats.unchanged_items + set_size(unchanged_ids)
    smart_stats.shops_scanned = smart_stats.shops_scanned + 1

    -- Step 6: Capture and remove deleted items
    if set_size(removed_ids_set) > 0 then
        Bodega.Parser.capture_removed_items(town, existing_shop, removed_ids_set, name)
        Bodega.Parser.remove_items_from_shop(existing_shop, removed_ids_set)
    end

    -- Step 7: Inspect new items
    local new_items = {}
    if set_size(new_ids) > 0 then
        local max_item_depth = tonumber(Opts.get("max-item-depth", 100))
        Log.out("Inspecting " .. set_size(new_ids) .. " new items for shop " .. shop_id, "smart")

        local current_time = iso_now()
        local count = 0
        for item_id in pairs(new_ids) do
            if count >= max_item_depth then break end
            local ok2, item_data = pcall(function()
                return Bodega.Parser.scan_item(item_id, current_items[item_id])
            end)
            if ok2 and item_data then
                new_items[#new_items + 1] = item_data
                Bodega.Parser.track_added_item(item_id, current_time, town, preamble, item_data)
            else
                Log.out("Failed to inspect item " .. item_id .. ": " .. tostring(item_data), "smart")
            end
            count = count + 1
        end
    end

    -- Step 8: Add new items to existing shop
    if #new_items > 0 then
        Bodega.Parser.add_items_to_shop(existing_shop, new_items)
    end

    -- Step 9: Update room_title for shop ID swaps during maintenance
    local preamble_shop_name = Bodega.Parser.extract_shop_name_from_preamble(preamble)
    if existing_shop.inv and existing_shop.inv[1] and preamble_shop_name ~= "unknown" then
        local current_room_title = existing_shop.inv[1].room_title or ""

        -- Extract shop type from current room_title
        local shop_type = nil
        local type_keywords = {
            "Magic Shoppe", "Weaponry", "Armory", "Outfitting", "General Store",
            "Combat Gear", "Locksmith Shop", "Boutique", "Treasures", "Cupboard",
            "Pantry", "Market", "Tower", "Stash", "Castle", "Eye", "Claw",
            "Kiss", "Ransom", "Den", "Hoard", "Goods", "Emporium", "Salon",
            "Parlor", "Imports", "Defence", "Couture", "Station", "Things",
            "Wares", "Snack Pantry", "Icemule Trade Station",
            "Confectionery Castle", "Smuggling Emporium", "Arcane Antiquities",
            "Fine Furs", "Supply Center", "Lost Things", "Lockpicks",
            "Trade Station", "Shop",
        }
        for _, tp in ipairs(type_keywords) do
            if current_room_title:find(tp, 1, true) then
                shop_type = tp
                break
            end
        end

        local new_room_title
        if shop_type and not preamble_shop_name:match("^[Tt]he%s") and not preamble_shop_name:match("^[Aa]%s") then
            new_room_title = preamble_shop_name .. "'s " .. shop_type
        elseif shop_type then
            new_room_title = preamble_shop_name .. " " .. shop_type
        else
            new_room_title = preamble_shop_name
        end

        existing_shop.inv[1].room_title = new_room_title
        Log.out("Updated room_title from '" .. current_room_title .. "' to '" .. new_room_title .. "'", "smart")
    end

    return {
        preamble = preamble,
        town = town,
        id = shop_id,
        inv = existing_shop.inv,
    }
end

function Bodega.Parser.extract_shop_name_from_preamble(preamble)
    if not preamble then return "unknown" end
    local name = preamble:match("^(.-)%'s?%s+Shop%s+is%s+located")
        or preamble:match("^(.-)%s+is%s+located")
    return name and trim(name) or "unknown"
end

-- Removed items tracking

function Bodega.Parser.load_removed_items()
    if removed_items_data then return removed_items_data end

    local path = Assets.local_path("removed_items.json")
    if File.exists(path) then
        local ok, data = pcall(function()
            return Json.decode(File.read(path))
        end)
        if ok and data then
            removed_items_data = data
            Log.out("Loaded removed_items.json", "smart")
        else
            removed_items_data = {}
        end
    else
        -- First run - check for migration from existing town files
        Log.out("No removed_items.json found, checking for migration...", "migrate")
        local migrated = {}

        local ok_towns, towns = pcall(Bodega.Parser.towns)
        if ok_towns then
            for _, town in ipairs(towns) do
                local ok2, td = pcall(Bodega.Parser.load_and_validate_town_json, town)
                if ok2 and td and td.removed_items and #td.removed_items > 0 then
                    migrated[town] = td.removed_items
                    Log.out("Migrating " .. #td.removed_items .. " removed items from " .. town .. ".json", "migrate")
                end
            end
        end

        removed_items_data = migrated

        if next(migrated) then
            Bodega.Parser.save_removed_items()
            Log.out("Migration complete - saved to removed_items.json", "migrate")
        else
            Log.out("No existing removed_items to migrate", "migrate")
        end
    end

    return removed_items_data
end

function Bodega.Parser.save_removed_items()
    if not removed_items_data or not next(removed_items_data) then return end

    -- Server reboot safeguard: check for mass additions
    local path = Assets.local_path("removed_items.json")
    if File.exists(path) then
        local ok, original = pcall(function()
            return Json.decode(File.read(path))
        end)
        if ok and original then
            local new_count = 0
            for town, items in pairs(removed_items_data) do
                local orig_items = original[town] or {}
                local orig_ids = {}
                for _, item in ipairs(orig_items) do
                    if item.id then orig_ids[tostring(item.id)] = true end
                end
                for _, item in ipairs(items) do
                    if item.id and not orig_ids[tostring(item.id)] then
                        new_count = new_count + 1
                    end
                end
            end

            local max_new = tonumber(Opts.get("removed-max-new", 750))
            if new_count > max_new then
                Log.out("SAFEGUARD: Rejecting " .. new_count .. " new removed items (threshold: " .. max_new .. ")", "safeguard")
                Log.out("This likely indicates a server reboot with ID reset - keeping existing data", "safeguard")
                return
            elseif new_count > 100 then
                Log.out("Adding " .. new_count .. " new removed items (threshold: " .. max_new .. ")", "safeguard")
            end
        end
    end

    local ok2, err = pcall(function()
        Assets.write_local_json(removed_items_data, "removed_items")
    end)
    if ok2 then
        Log.out("Saved removed_items.json", "smart")
    else
        Log.out("Failed to save removed_items.json: " .. tostring(err), "smart")
    end
end

function Bodega.Parser.capture_removed_items(town, shop_data, item_ids_set, shop_name)
    if not shop_data or not shop_data.inv then return end
    Bodega.Parser.load_removed_items()

    if not removed_items_data[town] then removed_items_data[town] = {} end
    local current_time = iso_now()

    for _, room in ipairs(shop_data.inv) do
        if room.items then
            for _, item in ipairs(room.items) do
                if item.id and item_ids_set[tostring(item.id)] then
                    local removed = {}
                    for k, v in pairs(item) do removed[k] = v end
                    removed.removed_date = current_time
                    removed.last_seen_shop = shop_name
                    removed.town = town
                    removed_items_data[town][#removed_items_data[town] + 1] = removed
                end
            end
        end
    end
end

function Bodega.Parser.remove_items_from_shop(shop_data, item_ids_set)
    if not shop_data or not shop_data.inv then return end
    for _, room in ipairs(shop_data.inv) do
        if room.items then
            local kept = {}
            for _, item in ipairs(room.items) do
                if not (item.id and item_ids_set[tostring(item.id)]) then
                    kept[#kept + 1] = item
                end
            end
            room.items = kept
        end
    end
end

function Bodega.Parser.add_items_to_shop(shop_data, new_items)
    if not shop_data or not shop_data.inv or #new_items == 0 then return end
    if #shop_data.inv == 0 then
        shop_data.inv = { { room_title = "Main Room", branch = "entry", items = {} } }
    end
    local first_room = shop_data.inv[1]
    if not first_room.items then first_room.items = {} end
    for _, item in ipairs(new_items) do
        first_room.items[#first_room.items + 1] = item
    end
end

function Bodega.Parser.get_removed_items_for_town(town)
    Bodega.Parser.load_removed_items()
    local all_removed = removed_items_data[town] or {}

    -- Deduplicate by item ID (keep most recent)
    local unique = {}
    for _, item in ipairs(all_removed) do
        local item_id = tostring(item.id or "")
        if item_id ~= "" then
            local existing = unique[item_id]
            if not existing then
                unique[item_id] = item
            else
                local existing_ts = parse_iso_time(existing.removed_date) or 0
                local new_ts = parse_iso_time(item.removed_date) or 0
                if new_ts > existing_ts then
                    unique[item_id] = item
                end
            end
        end
    end

    -- Sort by date (newest first)
    local sorted = {}
    for _, item in pairs(unique) do
        sorted[#sorted + 1] = item
    end
    table.sort(sorted, function(a, b)
        return (a.removed_date or "") > (b.removed_date or "")
    end)

    return sorted
end

-- Added items tracking

function Bodega.Parser.load_added_items()
    if added_items_data then return added_items_data end

    local path = Assets.local_path("added_items.json")
    if File.exists(path) then
        local ok, data = pcall(function()
            return Json.decode(File.read(path))
        end)
        if ok and data then
            added_items_data = data
            Log.out("Loaded added_items.json with " .. set_size(data) .. " items", "smart")
        else
            added_items_data = {}
        end
    else
        added_items_data = {}
    end

    return added_items_data
end

function Bodega.Parser.track_added_item(item_id, timestamp, town, preamble, item_data)
    Bodega.Parser.load_added_items()
    if town and preamble and item_data then
        local sig = Bodega.Parser.create_item_signature(town, preamble, item_data)
        if sig then
            added_items_data[sig] = timestamp
        else
            Log.out("Warning: Could not create signature for item " .. tostring(item_id), "smart")
        end
    end
end

function Bodega.Parser.create_item_signature(town, preamble, item_data)
    if not item_data or not item_data.name then return nil end
    local shop_name = Bodega.Parser.extract_shop_name_from_preamble(preamble)
    local price = (item_data.details and item_data.details.cost) or 0
    local safe_item = item_data.name:lower():match("^%s*(.-)%s*$") or ""
    return safe_string(town) .. ":" .. safe_string(shop_name) .. ":" .. safe_item .. ":" .. tostring(price)
end

function Bodega.Parser.save_added_items()
    if not added_items_data then return end

    -- Remove entries with invalid timestamps
    local cleaned = {}
    for sig, ts in pairs(added_items_data) do
        if parse_iso_time(ts) then
            cleaned[sig] = ts
        end
    end
    added_items_data = cleaned

    local ok, err = pcall(function()
        Assets.write_local_json(added_items_data, "added_items")
    end)
    if ok then
        Log.out("Saved added_items.json with " .. set_size(added_items_data) .. " items", "smart")
    else
        Log.out("Failed to save added_items.json: " .. tostring(err), "smart")
    end
end

function Bodega.Parser.clean_removed_items_by_size()
    local max_days = tonumber(Opts.get("removed-max-days", 180))
    local min_days = tonumber(Opts.get("removed-min-days", 14))
    local max_cutoff = os.time() - (max_days * 86400)

    -- First pass: remove anything older than max_days
    for town, items in pairs(removed_items_data) do
        local kept = {}
        for _, item in ipairs(items) do
            local ts = parse_iso_time(item.removed_date)
            if ts and ts >= max_cutoff then
                kept[#kept + 1] = item
            end
        end
        removed_items_data[town] = kept
    end

    -- Remove empty town entries
    local non_empty = {}
    for town, items in pairs(removed_items_data) do
        if #items > 0 then non_empty[town] = items end
    end
    removed_items_data = non_empty

    Bodega.Parser.save_removed_items()
end

function Bodega.Parser.display_smart_summary()
    if not smart_stats or smart_stats.shops_scanned == 0 then return end

    local total = smart_stats.new_items + smart_stats.unchanged_items
    local efficiency = total > 0 and math.floor(smart_stats.unchanged_items / total * 1000) / 10 or 0

    Log.out(string.rep("=", 60), "smart")
    Log.out("SMART PARSING SUMMARY", "smart")
    Log.out(string.rep("=", 60), "smart")
    Log.out("Shops scanned: " .. smart_stats.shops_scanned, "smart")
    Log.out("New items found: " .. smart_stats.new_items, "smart")
    Log.out("Items removed: " .. smart_stats.removed_items, "smart")
    Log.out("Items unchanged: " .. smart_stats.unchanged_items, "smart")
    Log.out(string.format("Cache efficiency: %.1f%% (%d/%d items cached)",
        efficiency, smart_stats.unchanged_items, total), "smart")

    if smart_stats.new_items > 0 or smart_stats.removed_items > 0 then
        Log.out("*** CHANGES DETECTED - JSON updated with " .. smart_stats.new_items ..
            " new and " .. smart_stats.removed_items .. " removed items ***", "smart")
    else
        Log.out("*** NO CHANGES DETECTED - All items matched cache ***", "smart")
    end
    Log.out(string.rep("=", 60), "smart")

    smart_stats = nil
end

function Bodega.Parser.scan_item(id, browse_price)
    local result = collect(
        "shop inspect " .. id,
        "You request a thorough inspection of",
        "You can use SHOP PURCHASE " .. id .. " to purchase",
        5
    )

    -- Extract details (skip first and last lines)
    local detail_lines = {}
    for i = 2, #result - 1 do
        detail_lines[#detail_lines + 1] = result[i]
    end

    local details = Bodega.Extractor.extract(detail_lines)

    -- Add browse price (more reliable than inspect parsing)
    if browse_price then
        details.cost = browse_price
    end

    -- Extract item name from first line, strip "from Owner's Shop." suffix
    local name = result[1]:gsub("You request a thorough inspection of ", "")
    name = name:gsub("%sfrom [A-Z].*%.$", "")

    return {
        id = id,
        name = name,
        details = details,
    }
end

function Bodega.Parser.towns_to_search()
    local town_filter = Opts.get("town")
    local towns = Bodega.Parser.towns()
    if not town_filter then return towns end
    local filtered = {}
    for _, town in ipairs(towns) do
        if town:lower():find(town_filter:lower(), 1, true) then
            filtered[#filtered + 1] = town
        end
    end
    return filtered
end

function Bodega.Parser.all()
    local results = {}
    for _, town in ipairs(Bodega.Parser.towns_to_search()) do
        results[#results + 1] = {
            town = town,
            shops = Bodega.Parser.shops(town),
        }
    end
    return results
end

function Bodega.Parser.to_json()
    local created_files = {}
    local all_town_data = {}

    Utils.benchmark("scan", "scanned shops in {{run_time}}", function()
        for _, town in ipairs(Bodega.Parser.towns_to_search()) do
            local start = os.time()
            local shops = Bodega.Parser.shops(town)
            local elapsed = os.time() - start

            all_town_data[#all_town_data + 1] = {
                created_at = iso_now(),
                run_time = fmt_time(elapsed),
                town = town,
                shops = shops or {},
            }
        end
    end)

    for _, data in ipairs(all_town_data) do
        local filename = Bodega.Parser.save_json(data.town, data)
        if filename then created_files[#created_files + 1] = filename end
    end

    -- Display smart summary if in smart mode
    if Opts.has("smart") then
        Bodega.Parser.display_smart_summary()
        Bodega.Parser.save_added_items()
    end

    -- Clean and save removed items
    if removed_items_data and next(removed_items_data) then
        Bodega.Parser.clean_removed_items_by_size()
        Bodega.Parser.save_removed_items()
    end

    -- Include removed_items.json in created files for upload
    if File.exists(Assets.local_path("removed_items.json")) then
        created_files[#created_files + 1] = "removed_items.json"
    end

    return created_files
end

function Bodega.Parser.save_json(name, data)
    if Opts.has("dry-run") then
        Utils.pp(data)
        return nil
    end
    local filename = safe_string(Opts.get("shop", name))
    Assets.write_local_json(data, filename)
    return filename .. ".json"
end

function Bodega.Parser.manifest()
    local url_root = Opts.get("url", "https://bodega.surge.sh")
    local assets = Assets.cached_files()
    if #assets == 0 then
        error("no assets found")
    end

    local asset_list = {}
    for _, asset in ipairs(assets) do
        local full_path = Assets.local_path(asset)
        local data = Utils.parse_json(File.read(full_path))
        asset_list[#asset_list + 1] = {
            url = url_root .. "/" .. asset,
            base_name = asset,
            checksum = Assets.checksum(asset),
            updated_at = data.created_at,
            run_time = data.run_time,
        }
    end

    local manifest = { created_at = iso_now(), assets = asset_list }
    Utils.pp(manifest)
    if not Opts.has("dry-run") then
        Assets.write_local_json(manifest, "manifest")
    end
end

-- Automation module methods for clean integration
function Bodega.Parser.smart_scan_auto()
    Log.out("Starting smart scan mode", "automation")
    Script.run("bodega", "parser --smart --save")
end

function Bodega.Parser.full_scan_auto()
    Log.out("Starting full scan mode", "automation")
    Script.run("bodega", "parser --smart --save")
    Script.run("bodega", "parser --save")
end

--------------------------------------------------------------------------------
-- Index: search index by id/keyword/shop/town
--------------------------------------------------------------------------------

Bodega.Index = {}
Bodega.Index.__index = Bodega.Index

local SPECIAL_GS_WORDS = { ora = true }

function Bodega.Index.new()
    local self = setmetatable({}, Bodega.Index)
    self:clear()
    return self
end

function Bodega.Index:clear()
    self.lookup = {
        by_keyword = {},
        by_id = {},
        by_shop = {},
        by_item = {},
        by_town = {},
    }
end

function Bodega.Index:by_id(id)
    return self.lookup.by_id[tostring(id)]
end

function Bodega.Index:has_id(id)
    return self:by_id(id) ~= nil
end

function Bodega.Index:add_id(id, obj)
    id = tostring(id)
    if self:has_id(id) then return end
    self.lookup.by_id[id] = obj
end

function Bodega.Index:_load(town_filter)
    town_filter = town_filter or "*"
    local files = Assets.cached_files()
    if town_filter ~= "*" then
        local filtered = {}
        for _, f in ipairs(files) do
            if f:find(town_filter, 1, true) then
                filtered[#filtered + 1] = f
            end
        end
        files = filtered
    end

    for _, file in ipairs(files) do
        local path = Assets.local_path(file)
        local data = Utils.read_json(path)
        if data.shops then
            for _, shop in ipairs(data.shops) do
                shop.id = (shop.town or "") .. (shop.id or "")
                self:add_id(shop.id, shop)
                if shop.inv then
                    for _, room in ipairs(shop.inv) do
                        if room.items then
                            for _, item in ipairs(room.items) do
                                local merged = {}
                                for k, v in pairs(item) do merged[k] = v end
                                merged.branch = room.branch
                                merged.room_title = room.room_title
                                self:add_id(item.id, merged)
                            end
                        end
                    end
                end
            end
        end
    end
end

function Bodega.Index:query(params)
    -- Placeholder for future search functionality
end

--------------------------------------------------------------------------------
-- SearchEngine: CDN sync and index management
--------------------------------------------------------------------------------

Bodega.SearchEngine = {}

function Bodega.SearchEngine.sync()
    local raw = Assets.get_remote("manifest.json")
    if not raw then return end
    local manifest = Utils.parse_json(raw)
    local assets = manifest.assets or {}

    local stale = {}
    for _, remote in ipairs(assets) do
        if Assets.is_stale(remote) or Opts.has("flush") then
            stale[#stale + 1] = remote
        end
    end

    if #stale == 0 then return end

    Utils.benchmark("download",
        string.format("%10s ... %20s >> {{run_time}}", "sync", "completed"),
        function()
            for _, remote in ipairs(stale) do
                local ok, err = pcall(Assets.stream_download, remote)
                if not ok then
                    Log.out(tostring(err), "error")
                end
            end
        end)
end

local _search_index = Bodega.Index.new()

function Bodega.SearchEngine.build_index()
    Utils.benchmark("index", "built index in {{run_time}}", function()
        _search_index:_load()
    end)
end

function Bodega.SearchEngine.get_index()
    return _search_index
end

function Bodega.SearchEngine.attach()
    Bodega.SearchEngine.sync()
    if Opts.has("force-index") then
        Bodega.SearchEngine.build_index()
    end
end

--------------------------------------------------------------------------------
-- Uploader: API-based multi-file upload with chunking for large files
--------------------------------------------------------------------------------

Bodega.Uploader = {}

local API_ENDPOINTS = {
    "https://bodega-netlify-api.netlify.app/.netlify/functions/upload",
    "https://bodega-vercel-api.vercel.app/api/upload",
}

function Bodega.Uploader.upload_all_files(specific_files)
    if Opts.has("dry-run") then return end

    Log.out("Starting upload process...", "upload")

    if Bodega.Uploader.upload_via_api(specific_files) then
        Log.out("Upload complete via API!", "upload")
    else
        Log.out("Upload failed - all API endpoints failed", "upload")
    end
end

function Bodega.Uploader.split_large_file(filename, json_content)
    local ok, data = pcall(Json.decode, json_content)
    if not ok or not data then
        Log.out(filename .. " failed to parse, cannot split", "upload")
        return { [filename] = json_content }
    end

    if not data.shops or type(data.shops) ~= "table" then
        Log.out(filename .. " doesn't have shops array, cannot split", "upload")
        return { [filename] = json_content }
    end

    local shops = data.shops
    local total_shops = #shops
    local chunk_size = 50
    local total_chunks = math.ceil(total_shops / chunk_size)
    local chunks = {}

    for chunk_num = 1, total_chunks do
        local start_idx = (chunk_num - 1) * chunk_size + 1
        local end_idx = math.min(chunk_num * chunk_size, total_shops)

        local shop_chunk = {}
        for i = start_idx, end_idx do
            shop_chunk[#shop_chunk + 1] = shops[i]
        end

        local base_name = filename:gsub("%.json$", "")
        local chunk_filename = string.format("%s_part%dof%d.json", base_name, chunk_num, total_chunks)

        local chunk_data = {}
        for k, v in pairs(data) do chunk_data[k] = v end
        chunk_data.shops = shop_chunk
        chunk_data.chunk_info = {
            original_file = filename,
            part = chunk_num,
            total_parts = total_chunks,
            shops_in_chunk = #shop_chunk,
            total_shops = total_shops,
        }

        local encoded = Json.encode(chunk_data)
        chunks[chunk_filename] = encoded
        Log.out("Created " .. chunk_filename .. ": " .. #shop_chunk .. " shops, " .. #encoded .. " bytes", "upload")
    end

    return chunks
end

function Bodega.Uploader.upload_via_api(specific_files)
    local files
    if specific_files and #specific_files > 0 then
        Log.out("Uploading specific files: " .. table.concat(specific_files, ", "), "upload")
        files = specific_files
    else
        Log.out("No specific files provided, uploading all cached files", "upload")
        files = Assets.cached_files()
    end

    if #files == 0 then
        Log.out("No files to upload", "upload")
        return true
    end

    -- Collect all files, splitting large ones
    local files_to_upload = {}
    for _, file in ipairs(files) do
        local basename = file:match("([^/]+)$") or file
        local path = Assets.local_path(basename)
        if File.exists(path) then
            local content = File.read(path)
            if content and #content > 5000000 then
                Log.out(basename .. " is large (" .. #content .. " bytes), splitting...", "upload")
                local split_files = Bodega.Uploader.split_large_file(basename, content)
                for name, data in pairs(split_files) do
                    files_to_upload[name] = data
                    Log.out("Preparing " .. name .. " for upload (" .. #data .. " bytes)", "upload")
                end
            else
                files_to_upload[basename] = content
                Log.out("Preparing " .. basename .. " for upload", "upload")
            end
        end
    end

    if not next(files_to_upload) then
        Log.out("No valid files to upload", "upload")
        return true
    end

    -- Try each API endpoint
    for _, endpoint in ipairs(API_ENDPOINTS) do
        local file_count = 0
        for _ in pairs(files_to_upload) do file_count = file_count + 1 end
        Log.out("Uploading " .. file_count .. " files to " .. endpoint .. " one by one...", "upload")

        local ok, result = pcall(Bodega.Uploader.upload_files_individually, endpoint, files_to_upload)
        if ok and result then
            Log.out("Successfully uploaded via API", "upload")
            return true
        elseif not ok then
            Log.out("Endpoint " .. endpoint .. " failed: " .. tostring(result), "upload")
        end
    end

    Log.out("All API endpoints failed", "upload")
    return false
end

function Bodega.Uploader.upload_files_individually(endpoint, files)
    local session_id = tostring(os.time()) .. tostring(math.random(1000))
    local total_files = 0
    for _ in pairs(files) do total_files = total_files + 1 end
    local file_index = 0

    Log.out("Starting multi-file upload session: " .. session_id, "upload")

    for filename, content in pairs(files) do
        file_index = file_index + 1
        local is_final = (file_index == total_files)

        local payload = {
            filename = filename,
            content = content,
            session_id = session_id,
            file_index = file_index,
            total_files = total_files,
            is_final = is_final,
            timestamp = os.date("%Y-%m-%d %H:%M:%S UTC"),
            source = "bodega-script-individual",
        }

        Log.out(string.format("Uploading %s (%d bytes) - %d/%d",
            filename, #content, file_index, total_files), "upload")

        local resp = Http.post_json(endpoint, payload, {
            ["User-Agent"] = "Bodega-Script/2.0",
        })

        if resp and resp.status >= 200 and resp.status < 300 then
            local ok, response_data = pcall(Json.decode, resp.body)
            if ok and response_data then
                Log.out(filename .. " uploaded: " .. (response_data.message or "ok"), "upload")
                if is_final and response_data.gist_url then
                    Log.out("Multi-file upload complete! Gist: " .. response_data.gist_url, "upload")
                    return true
                end
            end
        else
            local status = resp and resp.status or "unknown"
            Log.out("Failed to upload " .. filename .. " - HTTP " .. tostring(status), "upload")
            return false
        end

        if not is_final then
            pause(0.5)
        end
    end

    return true
end

function Bodega.Uploader.count_items_in_json(parsed_json)
    local total = 0
    if type(parsed_json) == "table" and parsed_json.shops then
        for _, shop in ipairs(parsed_json.shops) do
            if shop.inv then
                for _, room in ipairs(shop.inv) do
                    if room.items then
                        total = total + #room.items
                    end
                end
            end
        end
    end
    return total
end

--------------------------------------------------------------------------------
-- CLI: command routing and help
--------------------------------------------------------------------------------

Bodega.CLI = {}

function Bodega.CLI.help_menu()
    return "\n" ..
        "bodega v" .. VERSION .. "\n\n" ..
        "  this script uses the new playershop system by Naos to parse in-game shop directories\n" ..
        "  and generate JSON files that can be consumed by external systems.\n\n" ..
        "  This script also exposes the Bodega module that other scripts may call.\n\n" ..
        "parse mode:\n" ..
        "  --dry-run             run but print JSON to your FE                 [used primarily for testing]\n" ..
        "  --town                index all shops in one town                   [used primarily for testing]\n" ..
        "  --max-shop-depth      index only a certain number of shops per town [used primarily for testing]\n" ..
        "  --max-item-depth      index only a certain number of items per shop [used primarily for testing]\n" ..
        "  --shop                index a shop by name                          [used primarily for testing]\n" ..
        "  --save                dump the results to the filesystem            [required in standalone mode]\n" ..
        "  --out                 the location on the filesystem to write to    [defaults to data/bodega/]\n" ..
        "  --manifest            create a manifest file of the assets\n" ..
        "  --upload              upload generated JSON files via API\n\n" ..
        "smart mode:\n" ..
        "  --smart               enable smart parsing - only inspect new items for 90%+ speed boost\n" ..
        "                        loads existing JSON, compares item IDs, only inspects truly new items\n" ..
        "                        automatically removes deleted items and adds new ones\n" ..
        "                        first run still full speed, subsequent runs are much faster\n\n" ..
        "upload mode:\n" ..
        "  --upload              upload existing JSON files from local filesystem\n\n" ..
        "search mode:\n" ..
        "  --flush               forces a resync of the search index from the CDN\n" ..
        "  --force-index         forces the search index to be built as fast as possible\n\n"
end

function Bodega.CLI.run()
    Assets.init()

    if Opts.has("help") then
        respond(Bodega.CLI.help_menu())
        return
    end

    local ok, err = pcall(function()
        -- Parser mode
        if Opts.has("parser") then
            Log.out(Json.encode(Opts.to_table()), "opts")
            local created_files
            if Opts.has("save") or Opts.has("dry-run") then
                created_files = Bodega.Parser.to_json()
            end
            if Opts.has("manifest") then
                Bodega.Parser.manifest()
            end
            -- Auto-upload after parsing if requested
            if Opts.has("upload") and (Opts.has("save") or Opts.has("dry-run")) then
                Bodega.Uploader.upload_all_files(created_files)
            end
        end

        -- Standalone upload mode
        if Opts.has("upload") and not Opts.has("parser") then
            Log.out("Upload mode: uploading existing JSON files", "upload")
            Bodega.Uploader.upload_all_files()
        end

        -- Search mode
        if Opts.has("search") then
            Bodega.SearchEngine.attach()
        end
    end)

    if not ok then
        Log.out(tostring(err), "error")
    end
end

--------------------------------------------------------------------------------
-- Expose module globally for other scripts
--------------------------------------------------------------------------------

_G.Bodega = Bodega

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

Bodega.CLI.run()
