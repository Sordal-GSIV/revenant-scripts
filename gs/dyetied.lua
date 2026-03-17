--- @revenant-script
--- name: dyetied
--- version: 1.0.2
--- author: elanthia-online
--- contributors: Dissonance
--- game: gs
--- description: Dye crafting tracker -- find and share dyes from dye-n-ator/containers
--- tags: dyes,dye-n-ator,alchemy,cobbling,crafting
---
--- Changelog (from Lich5):
---   v1.0.2 (2025-05-12) - Updated Google Sheets URI
---   v1.0.1 (2025-05-09) - Extended timeout on sheet upload
---   v1.0.0 (2025-04-20) - Initial release

local debug_mode = CharSettings["dyetied_debug"] == "true"
local testing_mode = CharSettings["dyetied_testing"] == "true"

local dyes = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function pad_right(s, w) return (#s >= w) and s or (s .. string.rep(" ", w - #s)) end
local function pad_left(s, w)  return (#s >= w) and s or (string.rep(" ", w - #s) .. s) end

local function display_table()
    if #dyes == 0 then
        respond("No dyes found.")
        return
    end

    respond("")
    respond(pad_right("No", 4) .. pad_right("Item", 20) .. pad_right("Dye Name", 30) .. pad_right("Amount", 12) .. pad_right("Type", 12) .. "Character")
    respond(string.rep("-", 90))

    for i, dye in ipairs(dyes) do
        respond(pad_right(tostring(i), 4) .. pad_right(dye.item or "", 20) .. pad_right(dye.name or "", 30) .. pad_right(dye.amount or "", 12) .. pad_right(dye.dtype or "", 12) .. (dye.character or ""))
    end
    respond("")
end

--------------------------------------------------------------------------------
-- Dye-n-ator scanning
--------------------------------------------------------------------------------

local function scan_dyenator(item_name)
    dyes = {}
    fput("gaze " .. item_name)
    pause(2)

    -- Capture output via downstream for a short time
    local DYE_LINE_RX = Regex.new("(\\d+)\\.\\s+(infinite doses|\\d+ doses?) of (cobbling|alchemy) (.+?) dye")
    local captured = {}
    local HOOK = "dyetied_capture"

    DownstreamHook.add(HOOK, function(line)
        if not line then return line end
        local m = DYE_LINE_RX:match(line:gsub("<.->", ""))
        if m then
            dyes[#dyes + 1] = {
                name = m[4] .. " dye",
                amount = m[2],
                dtype = m[3],
                item = item_name,
                character = GameState.name,
            }
        end
        return line
    end)

    pause(3)
    DownstreamHook.remove(HOOK)

    echo("Found " .. #dyes .. " dye(s) in dye-n-ator.")
end

--------------------------------------------------------------------------------
-- Container scanning
--------------------------------------------------------------------------------

local function scan_container(item_name)
    dyes = {}
    -- Look in the container for dye items
    fput("look in my " .. item_name)
    pause(2)

    -- Simplified: look for dye items in game objects
    local inv = GameObj.inv()
    if inv then
        for _, item in ipairs(inv) do
            if item.name and item.name:lower():find("dye$") then
                dyes[#dyes + 1] = {
                    name = item.name,
                    amount = "unknown",
                    dtype = "unknown",
                    item = item_name,
                    character = GameState.name,
                }
            end
        end
    end

    echo("Found " .. #dyes .. " dye(s) in container.")
end

--------------------------------------------------------------------------------
-- Hand scanning
--------------------------------------------------------------------------------

local function scan_hand(hand)
    dyes = {}
    local obj = hand == "left" and GameObj.left_hand() or GameObj.right_hand()
    if not obj or not obj.name or not obj.name:lower():find("dye$") then
        echo("No dye found in " .. hand .. " hand.")
        return
    end

    -- Analyze to determine type
    fput("analyze #" .. obj.id)
    pause(2)

    dyes[#dyes + 1] = {
        name = obj.name,
        amount = "1",
        dtype = "unknown",
        item = "hand",
        character = GameState.name,
    }
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("DyeTied - Dye tracking and sharing")
    respond("")
    respond("  ;dyetied --dyenator <item>   Search for dyes in a dye-n-ator")
    respond("  ;dyetied --hand <left|right>  Record dye in hand")
    respond("  ;dyetied --container <item>   Record dyes in a container")
    respond("  ;dyetied --debug              Toggle debug mode")
    respond("  ;dyetied --testing-mode       Toggle testing mode (no upload)")
    respond("  ;dyetied --help               Show this help")
end

--------------------------------------------------------------------------------
-- CLI dispatch
--------------------------------------------------------------------------------

local arg0 = (Script.vars[0] or ""):lower()

if arg0:find("%-%-help") then
    show_help()
elseif arg0:find("%-%-debug") then
    debug_mode = not debug_mode
    CharSettings["dyetied_debug"] = tostring(debug_mode)
    echo("Debug mode: " .. tostring(debug_mode))
elseif arg0:find("%-%-testing") then
    testing_mode = not testing_mode
    CharSettings["dyetied_testing"] = tostring(testing_mode)
    echo("Testing mode: " .. tostring(testing_mode))
elseif arg0:find("%-%-dyenator") or arg0:find("%-%-dye%-n%-ator") then
    local item_name = table.concat(Script.vars, " ", 3)
    if item_name == "" then echo("Specify item name"); return end
    scan_dyenator(item_name)
    display_table()
elseif arg0:find("%-%-hand") then
    local hand = Script.vars[2] or "right"
    scan_hand(hand)
    display_table()
elseif arg0:find("%-%-container") then
    local item_name = table.concat(Script.vars, " ", 3)
    if item_name == "" then echo("Specify container name"); return end
    scan_container(item_name)
    display_table()
else
    show_help()
end
