--- sloot/gui.lua
-- Full tabbed setup GUI matching Lich5 sloot GTK layout.
-- 4 tabs: Sacks, Looting, Skinning, Selling.
-- Uses Revenant Gui API.

local settings_mod = require("sloot/settings")

local M = {}

--- Helper: create a labeled entry row and return the input widget.
local function entry_row(parent, label_text, value, tooltip)
    local row = Gui.hbox()
    local lbl = Gui.label(label_text)
    row:add(lbl)
    local inp = Gui.input({ text = value or "", placeholder = tooltip or "" })
    row:add(inp)
    parent:add(row)
    return inp
end

--- Helper: 2-column checkbox row
local function checkbox_row(parent, items)
    local row = Gui.hbox()
    for _, item in ipairs(items) do
        local cb = Gui.checkbox(item[1], item[2] or false)
        row:add(cb)
        item.widget = cb
    end
    parent:add(row)
end

--- Show the setup window.
-- Returns true if settings were saved.
function M.show(settings)
    local char_name = Char.name
    local win = Gui.window("SLoot configuration for " .. char_name,
        { width = 560, height = 580, resizable = false })
    local root = Gui.vbox()

    ---------------------------------------------------------------------------
    -- Tab bar
    ---------------------------------------------------------------------------
    local tabs = Gui.tab_bar({ "Sacks", "Looting", "Skinning", "Selling" })
    root:add(tabs)

    ---------------------------------------------------------------------------
    -- Tab 1: Sacks
    ---------------------------------------------------------------------------
    local pg1 = Gui.vbox()

    local sacks_frame = Gui.vbox()
    sacks_frame:add(Gui.section_header("Sacks"))
    sacks_frame:add(Gui.label("Specify a sack/container name for each loot type."))
    sacks_frame:add(Gui.separator())

    local function sack_row(parent, lbl1, key1, lbl2, key2)
        local row = Gui.hbox()
        row:add(Gui.label(lbl1))
        local i1 = Gui.input({ text = settings_mod.uvar_get(key1) })
        row:add(i1)
        if lbl2 then
            row:add(Gui.label(lbl2))
            local i2 = Gui.input({ text = settings_mod.uvar_get(key2) })
            row:add(i2)
            parent:add(row)
            return i1, i2
        end
        parent:add(row)
        return i1
    end

    local inp_ammo,   inp_box      = sack_row(sacks_frame, "Ammunition:", "ammosack",      "Boxes:",      "boxsack")
    local inp_gem,    inp_herb     = sack_row(sacks_frame, "Gems:",       "gemsack",       "Herbs:",      "herbsack")
    local inp_jewel,  inp_lock     = sack_row(sacks_frame, "Jewelry:",    "jewelrysack",   "Lockpicks:",  "lockpicksack")
    local inp_magic,  inp_reagent  = sack_row(sacks_frame, "Magical:",    "magicsack",     "Reagents:",   "reagentsack")
    local inp_scroll, inp_skin     = sack_row(sacks_frame, "Scrolls:",    "scrollsack",    "Skins:",      "skinsack")
    local inp_uncommon, inp_wand   = sack_row(sacks_frame, "Uncommon:",   "uncommonsack",  "Wands:",      "wandsack")
    local inp_clothing, inp_valuab = sack_row(sacks_frame, "Clothings:",  "clothingsack",  "Valuables:",  "valuablesack")
    -- Collectible + Overflow row (manual — overflow is CharSettings, not UserVars)
    local inp_collect, inp_overflow
    do
        local row = Gui.hbox()
        row:add(Gui.label("Collectible:"))
        inp_collect  = Gui.input({ text = settings_mod.uvar_get("collectiblesack") })
        row:add(inp_collect)
        row:add(Gui.label("(?) Overflow:"))
        inp_overflow = Gui.input({ text = settings.overflowsack or "",
            placeholder = "Comma-separated overflow sacks" })
        row:add(inp_overflow)
        sacks_frame:add(row)
    end

    pg1:add(Gui.scroll(sacks_frame))

    -- Locker sub-frame
    local locker_frame = Gui.vbox()
    locker_frame:add(Gui.section_header("Locker"))
    local inp_locker     = entry_row(locker_frame, "(?) Locker room:", settings.locker or "",
        "Room name/ID for your locker")
    local inp_locker_in  = entry_row(locker_frame, "(?) Locker in:",   settings.locker_in or "",
        "Comma-separated move commands to enter locker")
    local inp_locker_out = entry_row(locker_frame, "(?) Locker out:",  settings.locker_out or "",
        "Comma-separated move commands to exit locker")
    pg1:add(locker_frame)

    -- Advanced sub-frame
    local adv1_frame = Gui.vbox()
    adv1_frame:add(Gui.section_header("Advanced Options"))
    local chk_close_sacks = Gui.checkbox("(?) Keep sacks shut", settings.enable_close_sacks or false)
    adv1_frame:add(chk_close_sacks)
    pg1:add(adv1_frame)

    tabs:set_tab_content(1, Gui.scroll(pg1))

    ---------------------------------------------------------------------------
    -- Tab 2: Looting
    ---------------------------------------------------------------------------
    local pg2 = Gui.vbox()
    pg2:add(Gui.section_header("Looting"))
    pg2:add(Gui.label("Select loot categories and advanced looting options."))
    pg2:add(Gui.separator())

    local inp_crit_excl = entry_row(pg2, "(?) Exclude critters:", settings.critter_exclude or "",
        "Regex to skip critters")
    local inp_loot_excl = entry_row(pg2, "(?) Exclude loot:",    settings.loot_exclude or "",
        "Regex to skip loot items")

    local chk_search_all = Gui.checkbox("(?) Search all dead", settings.enable_search_all or false)
    pg2:add(chk_search_all)

    -- Loot type checkboxes (4 per row)
    local loot_cbs = {}
    local loot_keys = {
        { "Boxes",       "enable_loot_box"        },
        { "Gems",        "enable_loot_gem"        },
        { "Herbs",       "enable_loot_herb"       },
        { "Jewelry",     "enable_loot_jewelry"    },
        { "Lockpicks",   "enable_loot_lockpick"   },
        { "Magical",     "enable_loot_magic"      },
        { "Reagents",    "enable_loot_reagent"    },
        { "Scrolls",     "enable_loot_scroll"     },
        { "Skins",       "enable_loot_skin"       },
        { "Uncommon",    "enable_loot_uncommon"   },
        { "Valuables",   "enable_loot_valuable"   },
        { "Wands",       "enable_loot_wand"       },
        { "Clothings",   "enable_loot_clothing"   },
        { "Collectibles","enable_loot_collectible"},
    }
    local row = nil
    for i, entry in ipairs(loot_keys) do
        if (i - 1) % 4 == 0 then
            row = Gui.hbox()
            pg2:add(row)
        end
        local cb = Gui.checkbox(entry[1], settings[entry[2]] or false)
        loot_cbs[entry[2]] = cb
        row:add(cb)
    end

    pg2:add(Gui.section_header("Advanced Options"))
    local chk_disking   = Gui.checkbox("(?) Disking",       settings.enable_disking or false)
    local chk_stow_left = Gui.checkbox("(?) Stow left hand", settings.enable_stow_left or false)
    local chk_self_drops = Gui.checkbox("(?) Self loot only", settings.enable_self_drops or false)
    local chk_stance_start = Gui.checkbox("(?) Stance on start", settings.enable_stance_on_start or false)
    local row_adv = Gui.hbox()
    row_adv:add(chk_disking)
    row_adv:add(chk_stow_left)
    row_adv:add(chk_self_drops)
    row_adv:add(chk_stance_start)

    -- Phasing (Sorcerer only)
    local chk_phasing = nil
    if Char.prof == "Sorcerer" and Char.level > 3 and Spell.known(704) then
        chk_phasing = Gui.checkbox("(?) Phasing", settings.enable_phasing or false)
        row_adv:add(chk_phasing)
    end
    pg2:add(row_adv)

    local row_safe = Gui.hbox()
    local chk_safe_hiding = Gui.checkbox("(?) Safe hiding", settings.enable_safe_hiding or false)
    local inp_safe_ignore  = Gui.input({ text = settings.safe_ignore or "", placeholder = "NPC name regex to ignore" })
    inp_safe_ignore:set_sensitive(settings.enable_safe_hiding or false)
    chk_safe_hiding:on_click(function()
        inp_safe_ignore:set_sensitive(chk_safe_hiding:get_checked())
    end)
    row_safe:add(chk_safe_hiding)
    row_safe:add(inp_safe_ignore)
    pg2:add(row_safe)

    local row_gather = Gui.hbox()
    local chk_gather  = Gui.checkbox("(?) Gather ammo", settings.enable_gather or false)
    local inp_ammo_name = Gui.input({ text = settings.ammo_name or "", placeholder = "e.g. arrow, bolt" })
    inp_ammo_name:set_sensitive(settings.enable_gather or false)
    chk_gather:on_click(function()
        inp_ammo_name:set_sensitive(chk_gather:get_checked())
    end)
    row_gather:add(chk_gather)
    row_gather:add(inp_ammo_name)
    pg2:add(row_gather)

    tabs:set_tab_content(2, Gui.scroll(pg2))

    ---------------------------------------------------------------------------
    -- Tab 3: Skinning
    ---------------------------------------------------------------------------
    local pg3 = Gui.vbox()
    pg3:add(Gui.section_header("Skinning"))
    pg3:add(Gui.label("Configure skinning behavior, enhancements, and alternate weapon."))
    pg3:add(Gui.separator())

    local chk_skinning = Gui.checkbox("(?) Enable skinning", settings.enable_skinning or false)
    pg3:add(chk_skinning)

    pg3:add(Gui.section_header("Alternate Skinning Weapon"))
    local chk_skin_alt = Gui.checkbox("(?) Enable alternate", settings.enable_skin_alternate or false)
    pg3:add(chk_skin_alt)
    local inp_skinweapon     = entry_row(pg3, "Regular:",  settings_mod.uvar_get("skinweapon"),     "Weapon name for normal skinning")
    local inp_skinweaponsack = entry_row(pg3, "Sack:",     settings_mod.uvar_get("skinweaponsack"), "Container holding skin weapons")
    local inp_skinweaponblunt = entry_row(pg3, "Blunt:",   settings_mod.uvar_get("skinweaponblunt"), "Weapon for boulders/krynch/etc")

    pg3:add(Gui.section_header("Enhancements"))
    local chk_skin_off    = Gui.checkbox("(?) Skin in offensive",  settings.enable_skin_offensive or false)
    local chk_skin_kneel  = Gui.checkbox("(?) Kneel to skin",      settings.enable_skin_kneel or false)
    local chk_skin_safe   = Gui.checkbox("(?) Safe mode",          settings.enable_skin_safe_mode or false)
    local chk_skin_stance = Gui.checkbox("(?) Stance first",       settings.enable_skin_stance_first or false)
    local row_enh = Gui.hbox()
    row_enh:add(chk_skin_off)
    row_enh:add(chk_skin_kneel)
    row_enh:add(chk_skin_safe)
    row_enh:add(chk_skin_stance)

    local chk_skin_604  = nil
    local chk_skin_sigil = nil
    local show_spell_row = false
    if Char.prof == "Ranger" and Char.level > 3 and Spell.known(604) then
        chk_skin_604 = Gui.checkbox("(?) Use 604", settings.enable_skin_604 or false)
        show_spell_row = true
    end
    if Spell.known(9704) then
        chk_skin_sigil = Gui.checkbox("(?) Use Sigil of Resolve", settings.enable_skin_sigil or false)
        show_spell_row = true
    end
    pg3:add(row_enh)
    if show_spell_row then
        local row_sp = Gui.hbox()
        if chk_skin_604  then row_sp:add(chk_skin_604) end
        if chk_skin_sigil then row_sp:add(chk_skin_sigil) end
        pg3:add(row_sp)
    end

    pg3:add(Gui.section_header("Advanced Options"))
    local inp_stand_verb = entry_row(pg3, "(?) Stand verb:", settings.skin_stand_verb or "",
        "Custom verb to stand (blank = 'stand')")

    tabs:set_tab_content(3, Gui.scroll(pg3))

    ---------------------------------------------------------------------------
    -- Tab 4: Selling
    ---------------------------------------------------------------------------
    local pg4 = Gui.vbox()
    pg4:add(Gui.section_header("Selling"))
    pg4:add(Gui.label("Configure what to sell and advanced selling options."))
    pg4:add(Gui.separator())

    local inp_sell_excl = entry_row(pg4, "(?) Exclude loot:", settings.sell_exclude or "",
        "Regex to skip items during sell")

    local sell_type_cbs = {}
    local sell_keys = {
        { "Gems",        "enable_sell_type_gem"       },
        { "Jewelry",     "enable_sell_type_jewelry"   },
        { "Lockpicks",   "enable_sell_type_lockpick"  },
        { "Magical",     "enable_sell_type_magic"     },
        { "Reagents",    "enable_sell_type_reagent"   },
        { "Scrolls",     "enable_sell_type_scroll"    },
        { "Skins",       "enable_sell_type_skin"      },
        { "Wands",       "enable_sell_type_wand"      },
        { "Valuables",   "enable_sell_type_valuable"  },
        { "Clothings",   "enable_sell_type_clothing"  },
        { "Boxes as empties", "enable_sell_type_empty_box" },
        { "Scarabs to gemshop", "enable_sell_type_scarab" },
    }
    row = nil
    for i, entry in ipairs(sell_keys) do
        if (i - 1) % 4 == 0 then
            row = Gui.hbox()
            pg4:add(row)
        end
        local cb = Gui.checkbox(entry[1], settings[entry[2]] or false)
        sell_type_cbs[entry[2]] = cb
        row:add(cb)
    end

    pg4:add(Gui.section_header("Cleanup"))
    local row_cleanup = Gui.hbox()
    local chk_chrono   = Gui.checkbox("(?) Rings -> Chrono", settings.enable_sell_chronomage or false)
    local chk_share    = Gui.checkbox("(?) Share silvers",    settings.enable_sell_share_silvers or false)
    local inp_withdraw = Gui.input({ text = settings.sell_withdraw or "", placeholder = "Silvers to keep" })
    row_cleanup:add(chk_chrono)
    row_cleanup:add(chk_share)
    row_cleanup:add(Gui.label("(?) Withdraw:"))
    row_cleanup:add(inp_withdraw)
    pg4:add(row_cleanup)

    pg4:add(Gui.section_header("Boxes"))
    local row_boxes = Gui.hbox()
    local chk_locker_boxes = Gui.checkbox("(?) Enable lockering", settings.enable_locker_boxes or false)
    local chk_locksmith    = Gui.checkbox("(?) Enable locksmith", settings.enable_sell_locksmith or false)
    row_boxes:add(chk_locker_boxes)
    row_boxes:add(chk_locksmith)
    pg4:add(row_boxes)

    pg4:add(Gui.section_header("Bounties"))
    local chk_stockpile = Gui.checkbox("(?) Stockpile gems", settings.enable_sell_stockpile or false)
    pg4:add(chk_stockpile)

    tabs:set_tab_content(4, Gui.scroll(pg4))

    ---------------------------------------------------------------------------
    -- Save / Exit buttons
    ---------------------------------------------------------------------------
    local btn_row = Gui.hbox()
    local btn_save  = Gui.button("_Save & Close")
    local btn_close = Gui.button("E_xit")
    btn_row:add(btn_save)
    btn_row:add(btn_close)
    root:add(btn_row)

    win:set_root(root)
    win:show()

    local saved = false

    btn_save:on_click(function()
        -- ── UserVars (global sack names) ─────────────────────────────────
        settings_mod.uvar_set("ammosack",        inp_ammo:get_text())
        settings_mod.uvar_set("boxsack",         inp_box:get_text())
        settings_mod.uvar_set("gemsack",         inp_gem:get_text())
        settings_mod.uvar_set("herbsack",        inp_herb:get_text())
        settings_mod.uvar_set("jewelrysack",     inp_jewel:get_text())
        settings_mod.uvar_set("lockpicksack",    inp_lock:get_text())
        settings_mod.uvar_set("magicsack",       inp_magic:get_text())
        settings_mod.uvar_set("reagentsack",     inp_reagent:get_text())
        settings_mod.uvar_set("scrollsack",      inp_scroll:get_text())
        settings_mod.uvar_set("skinsack",        inp_skin:get_text())
        settings_mod.uvar_set("uncommonsack",    inp_uncommon:get_text())
        settings_mod.uvar_set("valuablesack",    inp_valuab:get_text())
        settings_mod.uvar_set("clothingsack",    inp_clothing:get_text())
        settings_mod.uvar_set("wandsack",        inp_wand:get_text())
        settings_mod.uvar_set("collectiblesack", inp_collect:get_text())
        settings_mod.uvar_set("skinweapon",      inp_skinweapon:get_text())
        settings_mod.uvar_set("skinweaponsack",  inp_skinweaponsack:get_text())
        settings_mod.uvar_set("skinweaponblunt", inp_skinweaponblunt:get_text())

        -- ── CharSettings (per-char local) ────────────────────────────────
        settings.overflowsack    = inp_overflow:get_text()
        settings.locker          = inp_locker:get_text()
        settings.locker_in       = inp_locker_in:get_text()
        settings.locker_out      = inp_locker_out:get_text()
        settings.enable_close_sacks = chk_close_sacks:get_checked()

        settings.critter_exclude = inp_crit_excl:get_text()
        settings.loot_exclude    = inp_loot_excl:get_text()
        settings.enable_search_all = chk_search_all:get_checked()

        for key, cb in pairs(loot_cbs) do
            settings[key] = cb:get_checked()
        end

        settings.enable_disking       = chk_disking:get_checked()
        settings.enable_stow_left     = chk_stow_left:get_checked()
        settings.enable_self_drops    = chk_self_drops:get_checked()
        settings.enable_stance_on_start = chk_stance_start:get_checked()
        if chk_phasing then settings.enable_phasing = chk_phasing:get_checked() end

        settings.enable_safe_hiding = chk_safe_hiding:get_checked()
        settings.safe_ignore        = inp_safe_ignore:get_text()
        settings.enable_gather      = chk_gather:get_checked()
        settings.ammo_name          = inp_ammo_name:get_text()

        settings.enable_skinning          = chk_skinning:get_checked()
        settings.enable_skin_alternate    = chk_skin_alt:get_checked()
        settings.enable_skin_offensive    = chk_skin_off:get_checked()
        settings.enable_skin_kneel        = chk_skin_kneel:get_checked()
        settings.enable_skin_safe_mode    = chk_skin_safe:get_checked()
        settings.enable_skin_stance_first = chk_skin_stance:get_checked()
        if chk_skin_604  then settings.enable_skin_604  = chk_skin_604:get_checked() end
        if chk_skin_sigil then settings.enable_skin_sigil = chk_skin_sigil:get_checked() end
        settings.skin_stand_verb          = inp_stand_verb:get_text()

        settings.sell_exclude              = inp_sell_excl:get_text()
        for key, cb in pairs(sell_type_cbs) do
            settings[key] = cb:get_checked()
        end
        settings.enable_sell_chronomage    = chk_chrono:get_checked()
        settings.enable_sell_share_silvers = chk_share:get_checked()
        settings.sell_withdraw             = inp_withdraw:get_text()
        settings.enable_locker_boxes       = chk_locker_boxes:get_checked()
        settings.enable_sell_locksmith     = chk_locksmith:get_checked()
        settings.enable_sell_stockpile     = chk_stockpile:get_checked()

        settings_mod.save(settings)
        respond("[SLoot] settings saved")
        saved = true
        win:close()
    end)

    btn_close:on_click(function()
        respond("[SLoot] closed without saving")
        win:close()
    end)

    Gui.wait(win, "close")
    return saved
end

return M
