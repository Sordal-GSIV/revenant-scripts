--- @revenant-script
--- @lic-certified: complete 2026-03-18
--- name: star_autoaccept
--- version: 2.0.0
--- author: unknown
--- game: gs
--- description: Automatically ACCEPTs trade offers. Whitelist mode restricts to named players only.
--- tags: accept, offer, give, trade
---
--- Original Lich5 sources: star-autoaccept.lic (core loop), autoaccept.lic by Ondreian (whitelist)
--- Ported to Revenant Lua.
---
--- Usage:
---   ;star_autoaccept              - run (accept from anyone, or whitelist-only if set)
---   ;star_autoaccept add <name>   - add player to whitelist
---   ;star_autoaccept remove <n>   - remove player by 1-based index
---   ;star_autoaccept list         - show whitelist
---   ;star_autoaccept clear        - clear whitelist (reverts to accept-all mode)
---   ;star_autoaccept help         - show usage

local HOOK_NAME    = "star_autoaccept_hook"
local SETTINGS_KEY = "star_autoaccept_whitelist"

-- Whitelist is a JSON-encoded array of lowercase player names.
-- Empty list = accept-all mode.
local function load_whitelist()
    local raw = CharSettings[SETTINGS_KEY]
    if raw and raw ~= "" then
        local ok, t = pcall(Json.decode, raw)
        if ok and type(t) == "table" then return t end
    end
    return {}
end

local function save_whitelist(list)
    if #list == 0 then
        CharSettings[SETTINGS_KEY] = nil
    else
        CharSettings[SETTINGS_KEY] = Json.encode(list)
    end
end

-- ── Sub-commands ──────────────────────────────────────────────────────────────

local cmd = (Script.vars[1] or ""):lower()

if cmd == "add" then
    local name = Script.vars[2]
    if not name or name == "" then
        echo("usage: ;star_autoaccept add <player_name>")
        return
    end
    local list = load_whitelist()
    local lc   = name:lower()
    for _, n in ipairs(list) do
        if n == lc then
            echo("'" .. name .. "' is already in the whitelist.")
            return
        end
    end
    table.insert(list, lc)
    save_whitelist(list)
    echo("Added '" .. name .. "' to whitelist (" .. #list .. " total). Now in whitelist-only mode.")
    return

elseif cmd == "remove" then
    local list = load_whitelist()
    local idx  = tonumber(Script.vars[2] or "0") or 0
    if idx < 1 or idx > #list then
        echo("Invalid index. Use ;star_autoaccept list to see entries.")
        return
    end
    local removed = table.remove(list, idx)
    save_whitelist(list)
    local suffix = (#list == 0) and " (whitelist empty — reverted to accept-all mode)" or ""
    echo("Removed '" .. removed .. "'." .. suffix)
    return

elseif cmd == "list" then
    local list = load_whitelist()
    if #list == 0 then
        echo("Whitelist is empty — accepting offers from everyone.")
    else
        echo("Whitelist (" .. #list .. " players — whitelist-only mode):")
        for i, name in ipairs(list) do
            respond("  " .. i .. ". " .. name)
        end
    end
    return

elseif cmd == "clear" then
    save_whitelist({})
    echo("Whitelist cleared. Now accepting from everyone.")
    return

elseif cmd == "help" or (cmd ~= "" and cmd ~= "on" and cmd ~= "start") then
    respond("star_autoaccept — auto-accept trade offers in GemStone IV")
    respond("  ;star_autoaccept              run (all players, or whitelist-only if set)")
    respond("  ;star_autoaccept add <name>   add player to whitelist")
    respond("  ;star_autoaccept remove <n>   remove by 1-based index")
    respond("  ;star_autoaccept list         show whitelist")
    respond("  ;star_autoaccept clear        clear whitelist (back to accept-all)")
    respond("  ;star_autoaccept help         this help")
    return
end

-- ── Runtime ───────────────────────────────────────────────────────────────────

local whitelist      = load_whitelist()
local whitelist_mode = #whitelist > 0

-- Fast lookup set (lowercase name → true)
local wl_set = {}
for _, n in ipairs(whitelist) do
    wl_set[n] = true
end

if whitelist_mode then
    echo("[star-autoaccept] Running. Accepting from " .. #whitelist .. " whitelisted player(s). Stop with ;kill star_autoaccept")
else
    echo("[star-autoaccept] Running. Accepting from anyone. Stop with ;kill star_autoaccept")
end

-- pending_offerer is set by the hook; the main loop clears it after accepting.
-- accepting flag prevents double-firing when multiple lines arrive during waitrt/fput.
local pending_offerer = nil
local accepting       = false

-- DownstreamHook receives raw XML; strip tags before pattern matching.
-- GS4 offer (stripped): "Playername offers you a/an/the <item>.  Click ACCEPT..."
-- Offerer is always a single capitalized word (GS4 player names have no spaces).
DownstreamHook.add(HOOK_NAME, function(line)
    if not line then return line end
    local stripped = line:gsub("<[^>]*>", "")
    local offerer  = stripped:match("^([A-Z][%a'%-]+) offers you ")
    if offerer then
        if not whitelist_mode or wl_set[offerer:lower()] then
            if not accepting then
                pending_offerer = offerer
            end
        end
    end
    return line
end)

before_dying(function()
    DownstreamHook.remove(HOOK_NAME)
    echo("[star-autoaccept] Stopped.")
end)

while true do
    if pending_offerer and not accepting then
        accepting = true
        local who = pending_offerer
        pending_offerer = nil
        waitrt()
        fput("ACCEPT")
        echo("[star-autoaccept] Accepted offer from " .. who .. ".")
        accepting = false
    end
    pause(0.1)
end
