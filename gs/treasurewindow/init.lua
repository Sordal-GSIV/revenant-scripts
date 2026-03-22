--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: treasurewindow
--- version: 1.5.0
--- author: Phocosoen, ChatGPT
--- game: gs
--- description: Real-time treasure & loot display — Wrayth panel + Revenant GUI window
---   with killtracker session summary integration
--- tags: wrayth, frontend, mod, window, treasures, gems, coins, loot, gui
---
--- Original Lich5 authors: Phocosoen, ChatGPT
--- Ported to Revenant Lua from treasurewindow.lic v1.4.7
---
--- Changelog (from Lich5 v1.4.7):
---   v1.5.0 (2026-03-19): Full Revenant rewrite.
---     GTK3 → Revenant Gui.* widget system (gui.lua module).
---     YAML window-settings file → CharSettings JSON (per-character, no file I/O).
---     $killtracker global hash → CharSettings["killtracker_data"] JSON read;
---       session totals shown (weekly/monthly GS4 reset tracking requires
---       killtracker.lua enhancement — not available in Revenant port yet).
---     $frontend check removed — Gui.* works for all frontends; Wrayth panel
---       (put() XML) is always emitted and ignored by non-Stormfront clients.
---     Ruby Regexp → Regex.new() for name/type filtering.
---     Lich's ;e eval links → upstream-hook-intercepted *tw_ commands.
---     *twgtk / *allgtk → *twwin aliases (Lich5 compat preserved).
---     All original features preserved: single/double column layout,
---     clickable loot links in Wrayth panel, killtracker summary,
---     *click / *twcol / *twwin upstream commands, persistent settings.
---   v1.4.7: Original Lich5 — Run GTK main asynchronously so startup hooks/loop
---     initialize reliably at logon.
---
--- Usage:
---   ;treasurewindow              — Start treasure window (Wrayth panel + GUI)
---   ;treasurewindow lootroom     — Loot the room and exit (called by Wrayth links)
---   ;treasurewindow eloot        — Start eloot and exit (called by Wrayth links)
---
--- In-game Commands (while running):
---   *click      — Toggle "Loot Room" / "Run Eloot" links in Wrayth panel + GUI
---   *twcol      — Toggle single / double column layout in Wrayth panel
---   *twwin      — Toggle Revenant GUI window open / closed
---   *twgtk      — Alias for *twwin (Lich5 compatibility)
---   *allgtk     — Alias for *twwin (Lich5 compatibility)

no_kill_all()

local gui = require("gui")

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function load_settings()
    local raw = CharSettings["treasurewindow_settings"]
    if raw and raw ~= "" then
        local ok, s = pcall(Json.decode, raw)
        if ok and type(s) == "table" then return s end
    end
    return { single_column = false, show_click_links = false, gui_open = true }
end

local function save_settings(s)
    CharSettings["treasurewindow_settings"] = Json.encode(s)
end

local settings = load_settings()

--------------------------------------------------------------------------------
-- XML helpers
--------------------------------------------------------------------------------

--- Escape a string for use in an XML attribute value.
local function xml_attr(s)
    if type(s) ~= "string" then s = tostring(s) end
    return s
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub("'", "&apos;")
        :gsub('"', "&quot;")
end

--- Format integer with comma separators (e.g. 12345 → "12,345").
local function with_commas(n)
    local s = string.format("%d", math.floor(n))
    return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

--------------------------------------------------------------------------------
-- Treasure filtering
--------------------------------------------------------------------------------

-- Names that should never appear as loot (fixtures, containers, special objs)
local EXCLUDE_NAMES_RE = Regex.new(
    "message board|cart|disk|door|patchworked saiful sphere|stairs|shop|" ..
    "swirled steel bowl full of sticks|wastebin|wide-mouthed wicker basket|" ..
    "rubbish bin|portal|barrel|arch|establishment|hut|gate|locksmith|" ..
    "firefly|cask|table|cafe|bench|shanty|plant|twisted pile of metal|" ..
    "puppy|flying .+? tome"
)

-- Object types we want to display
local TREASURE_TYPES_RE = Regex.new(
    "ammo|armor|box|clothing|collectible|cursed|gem|herb|jewelry|junk|" ..
    "magic|reagent|scarab|scroll|skin|uncommon|valuable|wand|weapon"
)

local function is_treasure(obj)
    local name = obj.name
    if name and EXCLUDE_NAMES_RE:test(name:lower()) then return false end
    local typ = obj.type
    return typ ~= nil and TREASURE_TYPES_RE:test(typ:lower())
end

local function filter_loot()
    local treasures = {}
    for _, obj in ipairs(GameObj.loot()) do
        if is_treasure(obj) then
            treasures[#treasures + 1] = obj
        end
    end
    return treasures
end

local function strip_article(name)
    return name
        :gsub("^[Aa]n?%s+", "")
        :gsub("^[Ss]ome%s+", "")
        :gsub("^[Tt]he%s+", "")
end

--- Compute a stable fingerprint for a treasure list so we can detect changes.
local function treasure_sig(treasures)
    local ids = {}
    for _, t in ipairs(treasures) do ids[#ids + 1] = t.id end
    table.sort(ids)
    return table.concat(ids, ",")
end

--------------------------------------------------------------------------------
-- Killtracker integration
-- Reads CharSettings["killtracker_data"] written by killtracker.lua.
-- NOTE: killtracker saves every 60 s, so data may lag by up to that interval.
-- Weekly / monthly GS4 reset tracking (weeks_gemstone, monthly_gemstones,
-- cached_reset_time) is not yet implemented in Revenant's killtracker.lua port;
-- session totals are shown instead.
--------------------------------------------------------------------------------

local function load_kt_data()
    local raw = CharSettings["killtracker_data"]
    if not raw or raw == "" then return nil end
    local ok, data = pcall(Json.decode, raw)
    if ok and type(data) == "table" then return data end
    return nil
end

--- Returns a flat list of display strings for the killtracker summary block.
local function kt_summary_lines()
    if not Script.running("killtracker") then return {} end
    local kt = load_kt_data()
    if not kt then return {} end

    local total_gems = 0
    for _, cnt in pairs(kt.gems or {}) do total_gems = total_gems + cnt end

    local total_jewels = 0
    for _, cnt in pairs(kt.jewels or {}) do total_jewels = total_jewels + cnt end

    local lines = {
        "Killtracker",
        "-------------------------",
        string.format("Kills:    %s",   with_commas(kt.total_kills   or 0)),
        string.format("Searches: %s",   with_commas(kt.total_searches or 0)),
        string.format("Gems:     %d",   total_gems),
        string.format("Dust:     %d",   kt.dust or 0),
    }
    if total_jewels > 0 then
        lines[#lines + 1] = string.format("Jewels:   %d", total_jewels)
    end
    lines[#lines + 1] = "-------------------------"
    return lines
end

--- Returns left/right column arrays for the two-column Wrayth killtracker block.
local function kt_two_columns()
    local kt = load_kt_data()
    if not kt then return nil, nil end

    local total_gems = 0
    for _, cnt in pairs(kt.gems or {}) do total_gems = total_gems + cnt end

    local total_jewels = 0
    for _, cnt in pairs(kt.jewels or {}) do total_jewels = total_jewels + cnt end

    local left = {
        "Kills:    " .. with_commas(kt.total_kills   or 0),
        "Gems:     " .. total_gems,
    }
    if total_jewels > 0 then
        left[#left + 1] = "Jewels: " .. total_jewels
    end

    local right = {
        "Searches: " .. with_commas(kt.total_searches or 0),
        "Dust:     " .. (kt.dust or 0),
    }
    return left, right
end

--------------------------------------------------------------------------------
-- Wrayth panel (Stormfront XML dialog)
-- put() routes XML dialog tags to the Wrayth frontend; non-Stormfront clients
-- ignore unknown XML gracefully.
--------------------------------------------------------------------------------

local WRAYTH_ID    = "TreasureWindow"
local ROW_H        = 20
local COL_LEFT     = 0
local COL_RIGHT    = 180

local function open_wrayth_panel()
    put(
        "<closeDialog id='" .. WRAYTH_ID .. "'/>" ..
        "<openDialog type='dynamic' id='" .. WRAYTH_ID .. "'" ..
        " title='Treasure' target='" .. WRAYTH_ID .. "'" ..
        " scroll='manual' location='main' justify='3' height='100'" ..
        " resident='true'>" ..
        "<dialogData id='" .. WRAYTH_ID .. "'></dialogData></openDialog>"
    )
end

local function close_wrayth_panel()
    put("<closeDialog id='" .. WRAYTH_ID .. "'/>")
end

--- Rebuild and push the full Wrayth panel content.
local function push_wrayth(treasures)
    local out = "<dialogData id='" .. WRAYTH_ID .. "' clear='t'>"
    local top = 0

    -- ── Killtracker block ─────────────────────────────────────────────────────
    if Script.running("killtracker") then
        if settings.single_column then
            -- Single column: one label per line
            for i, line in ipairs(kt_summary_lines()) do
                out = out .. string.format(
                    "<label id='kt_%d' value='%s' justify='left' left='%d' top='%d' />",
                    i, xml_attr(line), COL_LEFT, top
                )
                top = top + ROW_H
            end
        else
            -- Two-column layout: kills/gems | searches/dust
            local left, right = kt_two_columns()
            if left and right then
                out = out .. string.format(
                    "<label id='kt_title' value='Killtracker' justify='left' left='%d' top='%d' />",
                    COL_LEFT, top
                )
                top = top + ROW_H
                local max_rows = math.max(#left, #right)
                for i = 1, max_rows do
                    out = out .. string.format(
                        "<label id='kt_l%d' value='%s' justify='left' left='%d' top='%d' />",
                        i, xml_attr(left[i] or ""), COL_LEFT, top
                    )
                    out = out .. string.format(
                        "<label id='kt_r%d' value='%s' justify='left' left='%d' top='%d' />",
                        i, xml_attr(right[i] or ""), COL_RIGHT, top
                    )
                    top = top + ROW_H
                end
                out = out .. string.format(
                    "<label id='kt_div' value='-------------------------'" ..
                    " justify='left' left='%d' top='%d' />",
                    COL_LEFT, top
                )
                top = top + ROW_H
            end
        end
    end

    -- ── Click-to-loot links ───────────────────────────────────────────────────
    -- Links use *tw_run_eloot / the loot room command directly.
    -- *tw_run_eloot is intercepted by the upstream hook to start eloot.
    if settings.show_click_links then
        out = out .. string.format(
            "<link id='lootroom' value='Click to LOOT ROOM.'" ..
            " cmd='loot room' echo='Looting room...'" ..
            " fontSize='32' left='%d' top='%d' />",
            COL_LEFT, top
        )
        top = top + ROW_H
        out = out .. string.format(
            "<link id='eloot' value='Click to run ELOOT.'" ..
            " cmd='*tw_run_eloot' echo='Running eloot...'" ..
            " fontSize='32' left='%d' top='%d' />",
            COL_LEFT, top
        )
        top = top + ROW_H
        out = out .. string.format(
            "<label id='div_click' value='-------------------------'" ..
            " justify='left' left='%d' top='%d' />",
            COL_LEFT, top
        )
        top = top + ROW_H
    end

    -- ── Treasure count header ─────────────────────────────────────────────────
    out = out .. string.format(
        "<label id='treasuretotal' value='Treasures: %d' left='%d' top='%d' />",
        #treasures, COL_LEFT, top
    )
    top = top + ROW_H

    -- ── Treasure item links ───────────────────────────────────────────────────
    if settings.single_column then
        for i, t in ipairs(treasures) do
            local name = strip_article(t.name or t.noun or "?")
            out = out .. string.format(
                "<link id='treasure_%d' value='%s'" ..
                " cmd='get #%s' echo='get #%s'" ..
                " justify='bottom' left='%d' top='%d' />",
                i, xml_attr(name), t.id, t.id, COL_LEFT, top
            )
            top = top + ROW_H
        end
    else
        -- Two-column layout: items flow left→right, top→bottom
        local rows = math.ceil(#treasures / 2)
        local col_top = top
        for i, t in ipairs(treasures) do
            local name  = strip_article(t.name or t.noun or "?")
            local col   = (i - 1) % 2           -- 0 = left, 1 = right
            local row   = math.floor((i - 1) / 2)
            local left  = col == 0 and COL_LEFT or COL_RIGHT
            local item_top = col_top + row * ROW_H
            out = out .. string.format(
                "<link id='treasure_%d' value='%s'" ..
                " cmd='get #%s' echo='get #%s'" ..
                " justify='bottom' left='%d' top='%d' />",
                i, xml_attr(name), t.id, t.id, left, item_top
            )
        end
        top = col_top + rows * ROW_H
    end

    out = out .. "</dialogData>"
    put(out)
end

--------------------------------------------------------------------------------
-- Startup argument handling
-- ;treasurewindow lootroom  — sent by the Wrayth "Loot Room" link
-- ;treasurewindow eloot     — sent by the Wrayth "Run Eloot" link
--------------------------------------------------------------------------------

local startup_cmd = Script.vars[1]
if startup_cmd == "lootroom" then
    fput("loot room")
    return
elseif startup_cmd == "eloot" then
    if not Script.running("eloot") then
        Script.run("eloot")
    end
    return
end

--------------------------------------------------------------------------------
-- Upstream hook: intercept *tw_* commands and layout toggles
--------------------------------------------------------------------------------

local HOOK_ID = Script.name .. "_upstream"
UpstreamHook.remove(HOOK_ID)

UpstreamHook.add(HOOK_ID, function(command)
    if not command then return command end
    local cmd = command:match("^%s*(.-)%s*$"):lower()

    -- Toggle click-to-loot links in both Wrayth panel and GUI
    if cmd:find("^%*click") then
        settings.show_click_links = not settings.show_click_links
        save_settings(settings)
        respond("Click-to-loot links are now " ..
            (settings.show_click_links and "ENABLED" or "DISABLED") .. ".")
        return nil

    -- Toggle single / double column layout in Wrayth panel
    elseif cmd:find("^%*twcol") then
        settings.single_column = not settings.single_column
        save_settings(settings)
        respond("Column Layout: " .. (settings.single_column and "Single" or "Double"))
        return nil

    -- Toggle Revenant GUI window (*twwin / *twgtk / *allgtk)
    elseif cmd:find("^%*twwin") or cmd:find("^%*twgtk") or cmd:find("^%*allgtk") then
        if gui.is_open() then
            gui.close()
            settings.gui_open = false
            respond("Treasure GUI window closed.")
        else
            gui.create()
            settings.gui_open = true
            respond("Treasure GUI window opened.")
        end
        save_settings(settings)
        return nil

    -- Eloot link handler: start eloot script
    elseif cmd:find("^%*tw_run_eloot") then
        if not Script.running("eloot") then
            Script.run("eloot")
        end
        return nil
    end

    return command
end)

--------------------------------------------------------------------------------
-- Cleanup on exit
--------------------------------------------------------------------------------

before_dying(function()
    UpstreamHook.remove(HOOK_ID)
    close_wrayth_panel()
    gui.close()
end)

--------------------------------------------------------------------------------
-- Initialise windows
--------------------------------------------------------------------------------

open_wrayth_panel()
if settings.gui_open then
    gui.create()
end

echo("Treasurewindow is active.")

--------------------------------------------------------------------------------
-- Main loop
-- Polls GameObj.loot() at ~10 Hz; pushes updates when content changes or
-- every 2 s to keep timers current.
--------------------------------------------------------------------------------

local last_sig  = ""
local last_push = 0

while true do
    local now       = os.time()
    local treasures = filter_loot()
    local sig       = treasure_sig(treasures)

    if sig ~= last_sig or (now - last_push) >= 2 then
        last_sig  = sig
        last_push = now

        local kt_lines = kt_summary_lines()
        push_wrayth(treasures)
        gui.update(treasures, kt_lines, settings.show_click_links)
    end

    pause(0.1)
end
