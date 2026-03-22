--- @revenant-script
--- name: sloot
--- version: 3.5.2
--- author: SpiffyJr
--- contributors: Athias, Demandred, Tysong, Deysh, Ondreian, Lieo, Lobe, Etheirys
--- game: gs
--- description: Smart loot management — skin, search, loot, sort, sell
--- tags: loot,hunting,sell
---
--- Ported from Lich5 Ruby SpiffyLoot (sloot) v3.5.2
--- Original author: SpiffyJr <spiffyjr@gmail.com>
---
--- @lic-certified: complete 2026-03-19
---
--- Changelog (from Lich5):
---   3.5.2 (2025-10-21) Fix for nil UserVars, rubocop cleanup
---   3.5.1 (2021-11-02) Added COLLECTIBLE support, caederine stowing
---   3.5   (2020-03-19) Removing Gtk::Tooltips
---   3.4   (2019-01-15) Attempting fix for finding sacks for item TYPE in any order
---   3.3   (2017-12-18) Attempting to fix phasing for sorcerors
---   3.2   (2016-06-19) Updated get_item/put_item to not care about container
---   3.1   (2016-01-27) Sell boxes at pawn, sell scarabs at gemshop
---   3.0   (2015-11-19) Add massive boulder skinning
---
--- Usage:
---   ;sloot                   - Run skin/search/loot in current room
---   ;sloot sell              - Run automated selling routine
---   ;sloot deposit           - Deposit coins per settings
---   ;sloot setup             - Open GUI configuration
---   ;sloot left|right        - Loot from sack in hand
---   ;sloot stockpile-forget  - Clear stockpile jar memory
---   ;sloot stockpile-list    - List stockpiled gems
---   ;sloot reset-gui         - Reset GUI window position
---   ;sloot dump              - Dump current settings
---   ;sloot help              - Show help

local settings_mod  = require("sloot/settings")
local sacks_mod     = require("sloot/sacks")
local items_mod     = require("sloot/items")
local skinning_mod  = require("sloot/skinning")
local hooks_mod     = require("sloot/hooks")
local coins_mod     = require("sloot/coins")
local sell_mod      = require("sloot/sell")
local ammo_mod      = require("sloot/ammo")
local locker_mod    = require("sloot/locker")
local gui_mod       = require("sloot/gui")

-- Cleanup hooks on exit
before_dying(function()
    hooks_mod.remove_hooks()
end)

local cmd = ((Script.vars[1] or ""):lower()):match("^%s*(.-)%s*$")

--------------------------------------------------------------------------------
-- Load settings
--------------------------------------------------------------------------------
local settings = settings_mod.load()

--------------------------------------------------------------------------------
-- Command: setup
--------------------------------------------------------------------------------
if cmd == "setup" or cmd == "config" then
    gui_mod.show(settings)
    return

--------------------------------------------------------------------------------
-- Command: sell
--------------------------------------------------------------------------------
elseif cmd == "sell" then
    sacks_mod.find_sacks(settings, "sell")
    hooks_mod.install_hooks(settings)
    sell_mod.sell(settings)
    sacks_mod.close_open_sacks(settings)
    return

--------------------------------------------------------------------------------
-- Command: deposit
--------------------------------------------------------------------------------
elseif cmd == "deposit" then
    coins_mod.deposit_coins(settings)
    return

--------------------------------------------------------------------------------
-- Command: stockpile-forget
--------------------------------------------------------------------------------
elseif cmd == "stockpile-forget" then
    locker_mod.stockpile_forget()
    return

--------------------------------------------------------------------------------
-- Command: stockpile-list
--------------------------------------------------------------------------------
elseif cmd == "stockpile-list" then
    local filter = Script.vars[2]
    locker_mod.stockpile_list(filter)
    return

--------------------------------------------------------------------------------
-- Command: reset-gui
--------------------------------------------------------------------------------
elseif cmd == "reset-gui" then
    -- Gui window positions are managed by the frontend; nothing to reset in Revenant
    echo("[SLoot] GUI settings reset.")
    return

--------------------------------------------------------------------------------
-- Command: dump
--------------------------------------------------------------------------------
elseif cmd == "dump" then
    respond("[SLoot] Current settings:")
    for k, v in pairs(settings) do
        if type(v) == "table" then
            respond(string.format("  %-35s = [table]", k))
        else
            respond(string.format("  %-35s = %s", k, tostring(v)))
        end
    end
    return

--------------------------------------------------------------------------------
-- Command: left / right
--------------------------------------------------------------------------------
elseif cmd == "left" then
    sacks_mod.find_sacks(settings, cmd)
    local hand = GameObj.left_hand()
    if hand and hand.id then
        if not hand.contents then
            dothistimeout("look in #" .. hand.id, 5, Regex.new("^I could not find|In the .*\\."))
        end
        if hand.contents then
            items_mod.loot_it(hand.contents, {}, settings)
        else
            echo("[SLoot] failed to find contents of " .. (hand.name or "hand"))
        end
    end
    sacks_mod.close_open_sacks(settings)
    return

elseif cmd == "right" then
    sacks_mod.find_sacks(settings, cmd)
    local hand = GameObj.right_hand()
    if hand and hand.id then
        if not hand.contents then
            dothistimeout("look in #" .. hand.id, 5, Regex.new("^I could not find|In the .*\\."))
        end
        if hand.contents then
            items_mod.loot_it(hand.contents, {}, settings)
        else
            echo("[SLoot] failed to find contents of " .. (hand.name or "hand"))
        end
    end
    sacks_mod.close_open_sacks(settings)
    return

--------------------------------------------------------------------------------
-- Command: help / ?
--------------------------------------------------------------------------------
elseif cmd == "help" or cmd == "?" then
    local function msg(s) echo("[SLoot] " .. s) end
    msg("SLoot — Smart Loot Management v3.5.2")
    msg("  Author: SpiffyJr <spiffyjr@gmail.com>")
    msg("")
    msg("  ;sloot                  - skin, search, loot current room")
    msg("  ;sloot setup            - open GUI settings")
    msg("  ;sloot sell             - run automated selling routine")
    msg("  ;sloot deposit          - deposit coins to bank")
    msg("  ;sloot left             - loot container in left hand")
    msg("  ;sloot right            - loot container in right hand")
    msg("  ;sloot stockpile-forget - clear stockpile jar memory")
    msg("  ;sloot stockpile-list   - list stockpiled gems")
    msg("  ;sloot dump             - dump current settings")
    msg("  ;sloot reset-gui        - reset GUI window position")
    msg("  ;sloot help / ?         - this message")
    return

--------------------------------------------------------------------------------
-- Unknown command
--------------------------------------------------------------------------------
elseif cmd ~= "" then
    echo("[SLoot] Unknown command '" .. cmd .. "'. Try ;sloot help")
    return
end

--------------------------------------------------------------------------------
-- Default run: skin → search → loot
--------------------------------------------------------------------------------

-- Find sacks (exits on missing required sack)
local ok, err = pcall(function()
    sacks_mod.find_sacks(settings, nil)
end)
if not ok then
    echo("[SLoot] " .. tostring(err))
    return
end

-- Load alternate skin weapons if enabled
if settings.enable_skinning and settings.enable_skin_alternate then
    local ok2, err2 = pcall(function()
        skinning_mod.load_skin_weapons(settings)
    end)
    if not ok2 then
        echo("[SLoot] " .. tostring(err2))
        return
    end
end

-- Validate locker setting if locker_boxes enabled
if settings.enable_locker_boxes and (settings.locker or "") == "" then
    echo("[SLoot] ** lockering boxes is enabled but your locker is not set")
    return
end

-- Install hooks
hooks_mod.install_hooks(settings)

-- Record prev_stance
skinning_mod.set_prev_stance(checkstance() or "defensive")

-- Safe hiding check
if settings.enable_safe_hiding and hiding() then
    local safe_ignore = settings.safe_ignore or ""
    local bad = false
    for _, npc in ipairs(GameObj.npcs()) do
        if npc.status ~= "dead" and not Regex.test(npc.type or "", "escort") then
            if safe_ignore == "" or not Regex.test(npc.name or "", safe_ignore) then
                bad = true; break
            end
        end
    end
    if bad then return end
end

-- Track existing loot IDs for self-drops mode
local previous_loot_ids = {}
if settings.enable_self_drops then
    for _, l in ipairs(GameObj.loot()) do
        previous_loot_ids[l.id] = true
    end
end

-- Find dead critters
local function find_dead()
    local critter_exclude = settings.critter_exclude or ""
    local dead = {}
    for _, npc in ipairs(GameObj.npcs()) do
        if npc.status == "dead" then
            if critter_exclude == "" or not Regex.test(npc.name or "", critter_exclude) then
                dead[#dead + 1] = npc
            end
        end
    end
    return dead
end

local critters = find_dead()

-- ── Skinning ───────────────────────────────────────────────────────────────
if settings.enable_skinning then
    for _, critter in ipairs(critters) do
        if not Regex.test(critter.name or "", "Grimswarm")
           and not Regex.test(critter.type or "", "bandit") then
            skinning_mod.prepare_skinner(critter, settings)
            skinning_mod.skin_critter(critter, settings)
        end
    end
    skinning_mod.finish_skinner(settings)
end

-- ── Search dead creatures ──────────────────────────────────────────────────
local SEARCH_RX = Regex.new("^You search|^What were you referring to|You plunge your hand|withdraw a|causing assorted foliage|You quickly grab|you withdraw your arm to find a pungent")

for _, critter in ipairs(critters) do
    local res = dothistimeout("search #" .. critter.id, 5, SEARCH_RX)

    if res then
        if Regex.test(res, "withdraw a (?:cold blue gem|fiery red gem)") then
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            if rh and rh.noun == "gem" then
                items_mod.loot_it({ rh }, {}, settings)
            elseif lh and lh.noun == "gem" then
                items_mod.loot_it({ lh }, {}, settings)
            end
        elseif Regex.test(res, "you withdraw your arm to find a pungent piece") then
            -- Caederine: brute-force stow
            fput("stow caederine")
        end
    end

    -- Bramble patch loot (berry/thorn in hand)
    local rh2 = GameObj.right_hand()
    local lh2 = GameObj.left_hand()
    if rh2 and Regex.test(rh2.name or "", "berry|thorn") then
        fput("stow right")
    elseif lh2 and Regex.test(lh2.name or "", "berry|thorn") then
        fput("stow left")
    end

    if not settings.enable_search_all then break end
end

-- ── Stance on start ────────────────────────────────────────────────────────
if settings.enable_stance_on_start then
    skinning_mod.change_stance("defensive")
end

-- ── Loot ground items ──────────────────────────────────────────────────────
local target = GameObj.loot()
items_mod.loot_it(target, previous_loot_ids, settings)

-- ── Gather ammo ────────────────────────────────────────────────────────────
ammo_mod.gather_ammo(settings)

-- ── Restore hand contents ──────────────────────────────────────────────────
if settings.enable_stow_left then
    fill_left_hand()
else
    fill_right_hand()
end

-- ── Close opened sacks ────────────────────────────────────────────────────
sacks_mod.close_open_sacks(settings)
